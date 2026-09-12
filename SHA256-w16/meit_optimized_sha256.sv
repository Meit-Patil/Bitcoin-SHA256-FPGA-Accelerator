module simplified_sha256 #(parameter integer NUM_OF_WORDS = 20)(
 input logic  clk, reset_n, start,
 input logic  [15:0] message_addr, output_addr,
 output logic done, mem_clk, mem_we,
 output logic [15:0] mem_addr,
 output logic [31:0] mem_write_data,
 input logic [31:0] mem_read_data);

// FSM state variables 
enum logic [2:0] {IDLE, READ, ACTUAL_READ, BLOCK, COMPUTE, WRITE} state;


// Local variables

logic [31:0] w[16];
logic [31:0] message[NUM_OF_WORDS]; // Stores 20 message words after read from the memory ( changed this to NUM_OF_WORDS because what if we have data greater than 640 bits)
logic [31:0] wt;
logic [31:0] h0, h1, h2, h3, h4, h5, h6, h7;
logic [31:0] a, b, c, d, e, f, g, h;
logic [ 7:0] i, j;
logic [15:0] offset; // in word address
logic [ 7:0] num_blocks;
logic        cur_we;
logic [15:0] cur_addr;
logic [31:0] cur_write_data;
logic [512:0] memory_block;
logic [ 7:0] tstep;

logic [63:0] actual_size_bits;
logic [$clog2(NUM_OF_WORDS+1)-1:0] count;
logic [7:0] block_count;

logic[2:0] read_count;

logic first_pass;

logic[5:0] optimized_counter;

// SHA256 K constants
parameter int k[0:63] = '{
   32'h428a2f98,32'h71374491,32'hb5c0fbcf,32'he9b5dba5,32'h3956c25b,32'h59f111f1,32'h923f82a4,32'hab1c5ed5,
   32'hd807aa98,32'h12835b01,32'h243185be,32'h550c7dc3,32'h72be5d74,32'h80deb1fe,32'h9bdc06a7,32'hc19bf174,
   32'he49b69c1,32'hefbe4786,32'h0fc19dc6,32'h240ca1cc,32'h2de92c6f,32'h4a7484aa,32'h5cb0a9dc,32'h76f988da,
   32'h983e5152,32'ha831c66d,32'hb00327c8,32'hbf597fc7,32'hc6e00bf3,32'hd5a79147,32'h06ca6351,32'h14292967,
   32'h27b70a85,32'h2e1b2138,32'h4d2c6dfc,32'h53380d13,32'h650a7354,32'h766a0abb,32'h81c2c92e,32'h92722c85,
   32'ha2bfe8a1,32'ha81a664b,32'hc24b8b70,32'hc76c51a3,32'hd192e819,32'hd6990624,32'hf40e3585,32'h106aa070,
   32'h19a4c116,32'h1e376c08,32'h2748774c,32'h34b0bcb5,32'h391c0cb3,32'h4ed8aa4a,32'h5b9cca4f,32'h682e6ff3,
   32'h748f82ee,32'h78a5636f,32'h84c87814,32'h8cc70208,32'h90befffa,32'ha4506ceb,32'hbef9a3f7,32'hc67178f2
};

// Get num of blocks
assign num_blocks = determine_num_blocks(NUM_OF_WORDS); 
assign tstep = (optimized_counter - 1);


// Function to determine number of blocks in memory to fetch
function logic [15:0] determine_num_blocks(input logic [31:0] size);
  actual_size_bits = size * 32;
  if(actual_size_bits%512 == 0) begin
    determine_num_blocks = (actual_size_bits/512) +1;
  end
  else if(actual_size_bits%512 < 448) begin 
    determine_num_blocks = actual_size_bits/512+1;
  end
  else begin 
    determine_num_blocks = actual_size_bits/512 + 2;
  end
endfunction


// SHA256 hash round
function logic [255:0] sha256_op(input logic [31:0] a, b, c, d, e, f, g, h, w,
                                 input logic [7:0] t);
    logic [31:0] S1, S0, ch, maj, t1, t2; // internal signals
begin
    S1 = rightrotate(e, 6) ^ rightrotate(e, 11) ^ rightrotate(e, 25);
    ch = (e &f) ^ ((~ e) & g);
    t1 = h + S1 + ch + k[t] + w;
    S0 = (rightrotate(a,2)) ^ (rightrotate(a,13))^ (rightrotate(a,22));
    maj = (a & b) ^ (a & c) ^(b & c);
    t2 = S0 + maj;
    sha256_op = {t1 + t2, a, b, c, d + t1, e, f, g};
end
endfunction


// Generate request to memory
// for reading from memory to get original message
// for writing final computed has value
assign mem_clk = clk;
assign mem_addr = cur_addr + offset;
assign mem_we = cur_we;
assign mem_write_data = cur_write_data;


// Right Rotation Example : right rotate input x by r
// Right rotation function
function logic [31:0] rightrotate(input logic [31:0] x,
                                  input logic [ 7:0] r);
   rightrotate = (x >> r) | (x << (32 - r));
endfunction


function logic [31:0] compute_new_w (logic [7:0] position);
    logic [31:0] s0, s1;
    begin
        s0 = rightrotate(w[position -15],7) ^ rightrotate(w[position -15],18) ^ (w[position -15] >> 3);
        s1 = rightrotate(w[position -2],17) ^ rightrotate(w[position -2],19) ^ (w[position -2] >> 10);
        compute_new_w = w[position-16] + s0 + s1 + w[position -7];
    end
endfunction

// SHA-256 FSM 

always_ff @(posedge clk, negedge reset_n)
begin
  if (!reset_n) begin
    cur_we <= 1'b0;
    state <= IDLE;
  end 
  else case (state)
    // Initialize hash values h0 to h7 and a to h, other variables and memory we, address offset, etc
    IDLE: begin 
       if(start) begin
        h0 <= 32'h6a09e667; a <= 32'h6a09e667;
        h1 <= 32'hbb67ae85; b <= 32'hbb67ae85; 
        h2 <= 32'h3c6ef372; c <= 32'h3c6ef372; 
        h3 <= 32'ha54ff53a; d <= 32'ha54ff53a;
        h4 <= 32'h510e527f; e <= 32'h510e527f;
        h5 <= 32'h9b05688c; f <= 32'h9b05688c;
        h6 <= 32'h1f83d9ab; g <= 32'h1f83d9ab;
        h7 <= 32'h5be0cd19; h <= 32'h5be0cd19;
        cur_we <= '0;
        offset <= '0;
        cur_addr <= message_addr;
        state <= READ;
        count <='0;
        block_count <='0;
       end
       else begin
        state <= IDLE;
       end
    end

    

    READ: begin 
      if(count != NUM_OF_WORDS) begin
        state<= ACTUAL_READ;
      end
      else begin
        state<= BLOCK;
      end
    end

    ACTUAL_READ: begin  
      message[count] <=mem_read_data;
      count <= count + 1;
      offset <= offset + 1'b1;
      state <= READ;
    end




    // SHA-256 FSM  
    // Get a BLOCK from the memory, COMPUTE Hash output using SHA256 function    
    // and write back hash value back to memory
    BLOCK: begin
	// Fetch message in 512-bit block size
	// For each of 512-bit block initiate hash value computation
      if(block_count == num_blocks) begin 
        state <= WRITE;
        cur_we <=1;
        cur_addr <= output_addr;
        offset <='0;
        read_count <=0;
        cur_write_data<= h0;
      end
      else begin 
        state <= COMPUTE;
        i<='0;
        first_pass <=1;
        a <= h0;
        b <= h1;
        c <= h2;
        d <= h3;
        e <= h4;
        f <= h5;
        g <= h6;
        h <= h7;
        optimized_counter<=0;
        for(j=0;j<16;j=j+1) begin 
          if((16*block_count)+j < NUM_OF_WORDS) begin 
            w[j] <= message[(16*block_count)+j];
          end 
          else begin 
            if((16*block_count)+j == NUM_OF_WORDS) begin
              w[j] <= {1'b1,31'b0};
            end
            else begin 
              if(j==14) begin 
                w[j] <= actual_size_bits[63:32];
              end
              else if(j==15) begin 
                w[j] <= actual_size_bits[31:0];
              end
              else begin 
                w[j] <= '0;
              end
            end
          end
        end

      end

    end

    // For each block compute hash function
    // Go back to BLOCK stage after each block hash computation is completed and if
    // there are still number of message blocks available in memory otherwise
    // move to WRITE stage
    COMPUTE: begin

	    // 64 processing rounds steps for 512-bit block

        if(i<4) begin 
            state <= COMPUTE;
            if(optimized_counter < 16 && first_pass) begin 
                optimized_counter <= optimized_counter +1;
                {a,b,c,d,e,f,g,h} <= sha256_op(a,b,c,d,e,f,g,h,w[optimized_counter],((16*i)+optimized_counter));
            end
            else if (optimized_counter <= 16) begin
                optimized_counter <= optimized_counter +1;
                if(optimized_counter<16) begin
                    for(int m = 0; m<15; m++) begin 
                        w[m] <= w[m+1];
                    end
                    w[15] <= compute_new_w(16);
                    if(optimized_counter > 0) begin
                        {a,b,c,d,e,f,g,h} <= sha256_op(a,b,c,d,e,f,g,h,w[15],((16*i)+tstep));
                    end
                    else begin
                        //pass
                    end
                end
                else begin
                    if(!first_pass) begin
                        {a,b,c,d,e,f,g,h} <= sha256_op(a,b,c,d,e,f,g,h,w[15],((16*i)+tstep));
                    end
                end
            end
            else begin
                if(i == 0) begin
                    first_pass <= 0;
                end
                i <= i + 1;
                optimized_counter <= 0;
            end
        end
        else begin 
          block_count <= block_count + 1;
          state <= BLOCK;
          h0 <= h0 + a;
          h1 <= h1 + b;
          h2 <= h2 + c;
          h3 <= h3 + d;
          h4 <= h4 + e;
          h5 <= h5 + f;
          h6 <= h6 + g;
          h7 <= h7 + h;
        end
    end

    // h0 to h7 each are 32 bit hashes, which makes up total 256 bit value
    // h0 to h7 after compute stage has final computed hash value
    // write back these h0 to h7 to memory starting from output_addr
    WRITE: begin
      offset <= offset+1;
      if(read_count != 7) begin
        state <= WRITE;
        read_count <= read_count+1;
        if(read_count==0) begin 
          cur_write_data <= h1;
        end
        else if(read_count == 1) begin  
          cur_write_data <= h2;
        end
        else if(read_count == 2) begin  
          cur_write_data <= h3;
        end
        else if(read_count == 3) begin  
          cur_write_data <= h4;
        end
        else if(read_count == 4) begin  
          cur_write_data <= h5;
        end
        else if(read_count == 5) begin  
          cur_write_data <= h6;
        end
        else if(read_count == 6) begin  
          cur_write_data <= h7;
        end
      end
      else begin
        state <= IDLE;
        cur_we <= 0;
      end


    end
   endcase
  end

// Generate done when SHA256 hash computation has finished and moved to IDLE state
assign done = (state == IDLE);

endmodule