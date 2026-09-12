module bitcoin_hash (input logic        clk, reset_n, start,
                     input logic [15:0] message_addr, output_addr,
                    output logic        done, mem_clk, mem_we,
                    output logic [15:0] mem_addr,
                    output logic [31:0] mem_write_data,
                     input logic [31:0] mem_read_data);


enum logic [ 4:0]{IDLE, READ, ACTUAL_READ, COMPUTE_PH1, COMPUTE_PH2, COMPUTE_PH3, WRITE, DONE} state;


assign mem_clk = clk;

logic [31:0] input_message [19:0];
logic [4:0] block_read_counter;
logic [4:0] offset;
logic [31:0] inter_h0, inter_h1, inter_h2, inter_h3, inter_h4, inter_h5, inter_h6, inter_h7;
logic [31:0] pre_h0 [7:0];
logic [31:0] pre_h1 [7:0];
logic [31:0] pre_h2 [7:0];
logic [31:0] pre_h3 [7:0];
logic [31:0] pre_h4 [7:0];
logic [31:0] pre_h5 [7:0];
logic [31:0] pre_h6 [7:0];
logic [31:0] pre_h7 [7:0];

logic [7:0][31:0] final_hash [7:0]; 

logic phase_1_done;
logic phase_1_start;

logic [7:0] phase_2_done ;
logic phase_2_start;

logic [7:0]phase_3_done;
logic phase_3_start;


logic [3:0] write_offset;

logic [1:0] phase_counter;

logic [4:0] write_counter;

logic [3:0] batch_base;


localparam logic [31:0] h0_orig = 32'h6a09e667;
localparam logic [31:0] h1_orig = 32'hbb67ae85;
localparam logic [31:0] h2_orig = 32'h3c6ef372;
localparam logic [31:0] h3_orig = 32'ha54ff53a;
localparam logic [31:0] h4_orig = 32'h510e527f;
localparam logic [31:0] h5_orig = 32'h9b05688c;
localparam logic [31:0] h6_orig = 32'h1f83d9ab;
localparam logic [31:0] h7_orig = 32'h5be0cd19;

always_ff@(posedge clk, negedge reset_n) begin 
    if(!reset_n) begin 
        state <= IDLE;
        phase_1_start<=0;
        phase_2_start<=0;
        phase_3_start <=0;
        done <=0;
        mem_we<=0;
    end
    else begin
        case(state)

            IDLE: begin
            done <=0;
                if(start)begin
                    state <= READ;
                    mem_addr <= message_addr;
                    mem_we <= '0;
                    block_read_counter <=0;
                    offset <= 1'b1 ;
                end
                else begin 
                    state <= IDLE;
                end
            end

            READ : begin 
                if(block_read_counter == 19) begin
                    state <= COMPUTE_PH1;
                    phase_1_start <= 1;
                end 
                else begin
                    state <= ACTUAL_READ;
                end
            end

            ACTUAL_READ : begin
                input_message[block_read_counter] <= mem_read_data;
                block_read_counter <= block_read_counter + 1;
                mem_addr <= message_addr + offset;
                offset <= offset + 1;
                state <= READ;
            end

            COMPUTE_PH1 : begin 
                phase_1_start <= 0;
                if(phase_1_done) begin
                    state <= COMPUTE_PH2;
                    phase_2_start <=1;
                    write_offset <=0;
                    phase_counter <= 0;
                    batch_base <=0;
                end
                else begin
                    state <= COMPUTE_PH1;
                    
                end
            end

            COMPUTE_PH2 : begin 
                phase_2_start <=0;
                if(phase_counter == 2) begin
                    write_offset <=0;
                    state <= DONE;
                end
                else begin
                    if(&phase_2_done) begin
                        state <= COMPUTE_PH3;
                        phase_3_start <= 1;
                    end
                    else begin 
                        state <= COMPUTE_PH2;
                    end
                end
            end

            COMPUTE_PH3 : begin 
                phase_3_start <=0;
                if(&phase_3_done) begin 
                    state <= WRITE;
                    write_counter <= 0;
                end
                else begin
                    state <= COMPUTE_PH3;
                end
            end

            WRITE : begin 
                if(write_counter == 8) begin
                    phase_counter <= phase_counter + 1;
                    state <= COMPUTE_PH2;
                    if(phase_counter == 0) begin 
                        phase_2_start <= 1;
                        batch_base<=4'd8;
                    end
                    mem_we<=0;
                end
                else begin 
                    mem_we <= 1;
                    state <= WRITE;
                    mem_addr <= output_addr + write_offset;
                    write_offset<= write_offset +1;
                    mem_write_data <= final_hash[write_counter][0];
                    write_counter <= write_counter+1;
                end
            end



            DONE : begin
                state <= IDLE;
                done <=1;
            end
        endcase
        
    end
end

bitcoin_sha phase_1(
    .h0(h0_orig),
    .h1(h1_orig),
    .h2(h2_orig),
    .h3(h3_orig),
    .h4(h4_orig),
    .h5(h5_orig),
    .h6(h6_orig),
    .h7(h7_orig),
    .h0_out(inter_h0),
    .h1_out(inter_h1),
    .h2_out(inter_h2),
    .h3_out(inter_h3),
    .h4_out(inter_h4),
    .h5_out(inter_h5),
    .h6_out(inter_h6),
    .h7_out(inter_h7),
    .done(phase_1_done),
    .start(phase_1_start),
    .clk(clk),
    .reset_n(reset_n),
    .input_message({input_message[15],input_message[14],input_message[13],input_message[12],input_message[11],input_message[10],input_message[9],input_message[8],input_message[7],input_message[6],input_message[5],input_message[4],input_message[3],input_message[2],input_message[1],input_message[0]})
);



genvar m;
generate
    for(m=0; m<8; m++) begin : multiple_ph_2 
        wire [31:0] nonce_w = batch_base + m;
        bitcoin_sha inst_ph_2(
            .h0(inter_h0),
            .h1(inter_h1),
            .h2(inter_h2),
            .h3(inter_h3),
            .h4(inter_h4),
            .h5(inter_h5),
            .h6(inter_h6),
            .h7(inter_h7),
            .h0_out(pre_h0[m]),
            .h1_out(pre_h1[m]),
            .h2_out(pre_h2[m]),
            .h3_out(pre_h3[m]),
            .h4_out(pre_h4[m]),
            .h5_out(pre_h5[m]),
            .h6_out(pre_h6[m]),
            .h7_out(pre_h7[m]),
            .done(phase_2_done[m]),
            .start(phase_2_start),
            .clk(clk),
            .reset_n(reset_n),
            .input_message({32'd640,32'h00000000,32'h00000000,32'h00000000,32'h00000000,32'h00000000,32'h00000000,32'h00000000,32'h00000000,32'h00000000,32'h00000000,32'h80000000,nonce_w, input_message[18],input_message[17],input_message[16]})
        );
    end
endgenerate

genvar k;
generate
    for(k=0; k<8; k++) begin : multiple_ph_3 
        bitcoin_sha inst_ph_3(
            .h0(h0_orig),
            .h1(h1_orig),
            .h2(h2_orig),
            .h3(h3_orig),
            .h4(h4_orig),
            .h5(h5_orig),
            .h6(h6_orig),
            .h7(h7_orig),
            .h0_out(final_hash[k][0]),
            .h1_out(final_hash[k][1]),
            .h2_out(final_hash[k][2]),
            .h3_out(final_hash[k][3]),
            .h4_out(final_hash[k][4]),
            .h5_out(final_hash[k][5]),
            .h6_out(final_hash[k][6]),
            .h7_out(final_hash[k][7]),
            .done(phase_3_done[k]),
            .start(phase_3_start),
            .clk(clk),
            .reset_n(reset_n),
            .input_message({32'd256,32'h00000000,32'h00000000,32'h00000000,32'h00000000,32'h00000000,32'h00000000,32'h80000000,pre_h7[k],pre_h6[k],pre_h5[k],pre_h4[k],pre_h3[k],pre_h2[k],pre_h1[k],pre_h0[k]})
        );
    end
endgenerate



endmodule
