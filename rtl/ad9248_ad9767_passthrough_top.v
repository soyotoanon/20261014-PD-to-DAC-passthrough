`timescale 1ns / 1ps

// Low-speed wiring/functional test for the user's AD9248 V1.0 and ACM9767 V1.3.
//
// The FPGA forwards a 5 MHz clock to the ADC module.  The pictured module has
// one 14-bit multiplexed bus, so data after the rising and falling ADC clock
// edges are captured as two channels.  A completed pair is then written to the
// two independent AD9767 ports.  There is intentionally no PID in this image.
module ad9248_ad9767_passthrough_top #(
    parameter integer ADC_HALF_PERIOD_CYCLES = 5, // 50 MHz / (2*5) = 5 MHz
    parameter integer SWAP_CHANNELS = 0,
    // 1 = invert the ADC data on its way to the DAC.
    // This module's analog front end is inverting (covering the PD RAISES the
    // raw code), so with only the two's-complement -> offset-binary fix the DAC
    // output moves in antiphase with the PD's own output.  Set to 0 to get the
    // raw, non-inverted behaviour back.
    parameter integer INVERT_POLARITY = 1
) (
    input  wire        sys_clk,
    input  wire        sys_rst_n,

    input  wire [13:0] adc_d,
    input  wire        adc_otr,
    output wire        adc_clk,
    output wire        adc_oeb_n,
    output wire        adc_pdn,

    output wire [13:0] da1_data,
    output wire        da1_clk,
    output wire        da1_wrt,
    output wire [13:0] da2_data,
    output wire        da2_clk,
    output wire        da2_wrt
);

    reg [7:0] div_count;
    reg       adc_clk_r;
    reg       capture_pending;
    reg       capture_high_phase;
    reg [13:0] rising_sample;

    reg [13:0] da1_data_r;
    reg [13:0] da2_data_r;
    reg        dac_strobe_r;
    reg [1:0]  dac_phase;

    // Normal acquisition levels for the module:
    // OEB is active low; PDN is active high.
    assign adc_oeb_n = 1'b0;
    assign adc_pdn   = 1'b0;
    assign adc_clk   = adc_clk_r;

    assign da1_data = da1_data_r;
    assign da2_data = da2_data_r;
    assign da1_clk  = dac_strobe_r;
    assign da1_wrt  = dac_strobe_r;
    assign da2_clk  = dac_strobe_r;
    assign da2_wrt  = dac_strobe_r;

    // Keep the otherwise diagnostic-only OTR input in the test top-level.
    wire unused_adc_otr = adc_otr;

    // The AD9248 V1.0 module is hardwired for two's-complement output (DFS is
    // not brought out to its header), while the AD9767 expects offset binary.
    // Flip the MSB so a mid-scale ADC input produces a mid-scale DAC output
    // instead of pinning the DAC near positive full scale.
    wire [13:0] adc_d_ob = adc_d ^ 14'h2000;

    // ...and the module's analog front end is inverting on top of that: a
    // brighter PD gives a MORE NEGATIVE input, so the code falls as the light
    // rises.  Inverting the whole offset-binary word (~code == 14'h3FFF - code)
    // is exactly a sign flip about mid-scale, which puts the DAC back in phase
    // with what the PD actually does.
    wire [13:0] adc_d_fmt = INVERT_POLARITY ? ~adc_d_ob : adc_d_ob;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            div_count          <= 8'd0;
            adc_clk_r          <= 1'b0;
            capture_pending    <= 1'b0;
            capture_high_phase <= 1'b0;
            rising_sample      <= 14'h2000;
            da1_data_r         <= 14'h2000;
            da2_data_r         <= 14'h2000;
            dac_strobe_r       <= 1'b0;
            dac_phase          <= 2'd0;
        end else begin
            // Toggle the forwarded ADC clock.  Sampling is delayed by one
            // 50 MHz cycle, giving the AD9248 data (2..6 ns tPD) ample time to
            // settle before it is read at this deliberately low test rate.
            if (div_count == ADC_HALF_PERIOD_CYCLES - 1) begin
                div_count          <= 8'd0;
                adc_clk_r          <= ~adc_clk_r;
                capture_pending    <= 1'b1;
                capture_high_phase <= ~adc_clk_r;
            end else begin
                div_count <= div_count + 8'd1;
            end

            if (capture_pending) begin
                capture_pending <= 1'b0;
                if (capture_high_phase) begin
                    rising_sample <= adc_d_fmt;
                end else begin
                    // The falling-edge sample completes a channel pair.
                    // Data is registered first; DAC strobes rise one 50 MHz
                    // cycle later, satisfying setup time with a wide margin.
                    if (SWAP_CHANNELS != 0) begin
                        da1_data_r <= adc_d_fmt;
                        da2_data_r <= rising_sample;
                    end else begin
                        da1_data_r <= rising_sample;
                        da2_data_r <= adc_d_fmt;
                    end
                    dac_phase <= 2'd1;
                end
            end

            case (dac_phase)
                2'd0: begin
                    dac_strobe_r <= 1'b0;
                end
                2'd1: begin
                    dac_strobe_r <= 1'b1;
                    dac_phase    <= 2'd2;
                end
                default: begin
                    dac_strobe_r <= 1'b0;
                    dac_phase    <= 2'd0;
                end
            endcase
        end
    end

endmodule

