module bitcoin_sha (
    input logic [31:0] h0,
    input logic [31:0] h1,
    input logic [31:0] h2,
    input logic [31:0] h3,
    input logic [31:0] h4,
    input logic [31:0] h5,
    input logic [31:0] h6,
    input logic [31:0] h7,
    output logic [31:0] h0_out,
    output logic [31:0] h1_out,
    output logic [31:0] h2_out,
    output logic [31:0] h3_out,
    output logic [31:0] h4_out,
    output logic [31:0] h5_out,
    output logic [31:0] h6_out,
    output logic [31:0] h7_out,
    output logic done,
    input logic start,
    input logic [15:0][31:0]input_message,
    input logic clk,
    input logic reset_n
);

enum logic [1:0] {IDLE, EXPAND, DONE} state;

logic [31:0] expanded_input [15:0];

logic[6:0] computation_counter;
logic[6:0] merged_counter;
logic first_pass;


logic[31:0] a,b,c,d,e,f,g,h;


parameter int k[64] = '{
    32'h428a2f98,32'h71374491,32'hb5c0fbcf,32'he9b5dba5,32'h3956c25b,32'h59f111f1,32'h923f82a4,32'hab1c5ed5,
    32'hd807aa98,32'h12835b01,32'h243185be,32'h550c7dc3,32'h72be5d74,32'h80deb1fe,32'h9bdc06a7,32'hc19bf174,
    32'he49b69c1,32'hefbe4786,32'h0fc19dc6,32'h240ca1cc,32'h2de92c6f,32'h4a7484aa,32'h5cb0a9dc,32'h76f988da,
    32'h983e5152,32'ha831c66d,32'hb00327c8,32'hbf597fc7,32'hc6e00bf3,32'hd5a79147,32'h06ca6351,32'h14292967,
    32'h27b70a85,32'h2e1b2138,32'h4d2c6dfc,32'h53380d13,32'h650a7354,32'h766a0abb,32'h81c2c92e,32'h92722c85,
    32'ha2bfe8a1,32'ha81a664b,32'hc24b8b70,32'hc76c51a3,32'hd192e819,32'hd6990624,32'hf40e3585,32'h106aa070,
    32'h19a4c116,32'h1e376c08,32'h2748774c,32'h34b0bcb5,32'h391c0cb3,32'h4ed8aa4a,32'h5b9cca4f,32'h682e6ff3,
    32'h748f82ee,32'h78a5636f,32'h84c87814,32'h8cc70208,32'h90befffa,32'ha4506ceb,32'hbef9a3f7,32'hc67178f2
};


function logic [31:0] rightrotate(input logic [31:0] x,
                                  input logic [ 7:0] r);
   rightrotate = (x >> r) | (x << (32 - r));
endfunction



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



function logic [31:0] compute_new_w (logic [7:0] position);
    logic [31:0] s0, s1;
    begin
        s0 = rightrotate(expanded_input[position -15],7) ^ rightrotate(expanded_input[position -15],18) ^ (expanded_input[position -15] >> 3);
        s1 = rightrotate(expanded_input[position -2],17) ^ rightrotate(expanded_input[position -2],19) ^ (expanded_input[position -2] >> 10);
        compute_new_w = expanded_input[position-16] + s0 + s1 + expanded_input[position -7];
    end
endfunction





always_ff@(posedge clk, negedge reset_n) begin 
    if(!reset_n) begin
        state <= IDLE;
        done <=0;
    end
    else begin
        case(state)

            IDLE: begin 
                done <=0;
                if(!start) begin
                    state <= IDLE;
                end
                else begin 
                    state <= EXPAND;
                    for(int i=0; i<16; i++) begin 
                        expanded_input[i] <= input_message[i];
                    end
                    computation_counter <= 0;
                    merged_counter <= 0;
                    first_pass <=1;
                    a<= h0;
                    b<= h1;
                    c<= h2;
                    d<= h3;
                    e<= h4;
                    f<= h5;
                    g<= h6;
                    h<= h7;
                end
            end


            EXPAND: begin 
                if(computation_counter == 64 ) begin
                    state <= DONE;
                end

                else begin
                    
                    if(merged_counter < 16 && first_pass) begin 
                        computation_counter <= computation_counter + 1;
                        state <= EXPAND;
                        merged_counter <= merged_counter + 1;
                        {a,b,c,d,e,f,g,h} <= sha256_op(a,b,c,d,e,f,g,h,expanded_input[computation_counter], computation_counter);
                    end
                    else if(merged_counter < 16) begin
                        state <= EXPAND;
                        merged_counter <= merged_counter + 1;
                        for(int m=0; m< 15; m++) begin 
                            expanded_input[m] <= expanded_input[m+1];
                        end
                        expanded_input[15] <= compute_new_w(16);
                        if(merged_counter >0 )begin 
                            computation_counter <= computation_counter + 1;
                            {a,b,c,d,e,f,g,h} <= sha256_op(a,b,c,d,e,f,g,h,expanded_input[15], computation_counter);
                        end
                    end

                    else if (merged_counter == 16 && !first_pass) begin 
                        state <= EXPAND;
                        merged_counter <= merged_counter+1;
                        computation_counter <= computation_counter + 1;
                        {a,b,c,d,e,f,g,h} <= sha256_op(a,b,c,d,e,f,g,h,expanded_input[15], computation_counter);
                    end

                    else begin 
                        state <= EXPAND;
                        merged_counter <=0;
                        first_pass <=0;
                    end
                end
            end




            DONE: begin 
                h0_out <= h0 + a;
                h1_out <= h1 + b;
                h2_out <= h2 + c;
                h3_out <= h3 + d;
                h4_out <= h4 + e;
                h5_out <= h5 + f;
                h6_out <= h6 + g;
                h7_out <= h7 + h;
                done <=1;
                state<= IDLE;
            end
        endcase
    end

end

endmodule


