// Code your testbench here
// or browse Examples
class transaction;
  
  logic newd;
  rand logic [7:0] tx_data;
  logic tx;
  logic donetx;
  logic [7:0] dout;
  
  function transaction copy();
    copy = new();
    copy.newd = this.newd;
    copy.tx_data = this.tx_data;
    copy.tx = this.tx;
    copy.donetx = this.donetx;
    copy.dout = this.dout;
  endfunction
  
endclass


class generator;
  
  transaction trans;
  mailbox #(transaction) mbx;
  event drv_next;
  event sco_next;
  event done;
  int count;
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
    trans = new();
  endfunction
  
  task run();
    for (int unsigned i=0; i<count; i++) begin
      assert(trans.randomize()) else $error("Randomization Failed");
      mbx.put(trans.copy());
      $display("--------------------------------------");
      $display("[GEN]");
      @(sco_next);
      @(drv_next);
      $display("[GEN]");
    end
    ->done;
  endtask
  
endclass


interface uarttx_if;
  logic clk, newd, rst;
  logic [7:0] tx_data; 
  logic tx, donetx;
  logic uclk;
endinterface


class driver;
  
  virtual uarttx_if vif;
  transaction trans;
  mailbox #(transaction) mbx;
  mailbox #(bit [7:0]) mbx_din;
  event drv_next;
  
  function new(mailbox #(transaction) mbx, mailbox #(bit [7:0]) mbx_din);
    this.mbx = mbx;
    this.mbx_din = mbx_din;
  endfunction
  
  task reset();
    vif.rst <= 1'b1;
    vif.newd <= 1'b0;
    vif.tx_data <= 8'b0;
    repeat(5) @(posedge vif.uclk);
    vif.rst <= 1'b0;
    @(posedge vif.uclk);
  endtask
  
  task run();
    forever begin
      mbx.get(trans);
      @(posedge vif.uclk);
      vif.tx_data <= trans.tx_data;
      vif.newd <= 1'b1;
      mbx_din.put(trans.tx_data);
      $display("[DRV]");
      @(posedge vif.uclk);
      vif.newd <= 1'b0;
      wait(vif.donetx == 1'b1);
      ->drv_next;
    end
  endtask
  
endclass


class monitor;
  
  virtual uarttx_if vif;
  transaction trans;
  mailbox #(transaction) mbx;
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
    trans = new();
  endfunction
  
  task run();
    forever begin
      @(posedge vif.uclk);
      if (vif.newd == 1'b1) begin
        @(posedge vif.uclk);
        for (int i=0; i<8; i++) begin
          @(posedge vif.uclk);
          trans.tx = vif.tx;
          trans.dout = {trans.tx, trans.dout[7:1]};
        end
        mbx.put(trans);
        $display("[MON]");
        @(posedge vif.uclk);
        @(posedge vif.uclk);
      end
    end
  endtask
  
endclass


class scoreboard;
  
  transaction trans;
  bit [7:0] din;
  mailbox #(transaction) mbx;
  mailbox #(bit [7:0]) mbx_din;
  event sco_next;
  
  function new(mailbox #(transaction) mbx, mailbox #(bit [7:0]) mbx_din);
    this.mbx = mbx;
    this.mbx_din = mbx_din;
  endfunction
  
  task run();
    forever begin
      mbx.get(trans);
      mbx_din.get(din);
      $display("trans.dout = %d", trans.dout);
      $display("din = %d", din);
      if (trans.dout == din) begin
        $display("Pass");
      end else begin
        $display("Fail");
      end
      $display("[SCO]");
      $display("--------------------------------------");
      ->sco_next;
    end
  endtask
  
endclass


class environment;
  
  virtual uarttx_if vif;
  generator gen;
  driver drv;
  monitor mon;
  scoreboard sco;
  mailbox #(transaction) mbx_g2d;
  mailbox #(transaction) mbx_m2s;
  mailbox #(bit [7:0]) mbx_din;
  
  function new(virtual uarttx_if vif);
    this.vif = vif;
    mbx_g2d = new();
    mbx_m2s = new();
    mbx_din = new();
    gen = new(mbx_g2d);
    drv = new(mbx_g2d, mbx_din);
    mon = new(mbx_m2s);
    sco = new(mbx_m2s, mbx_din);
    drv.vif = this.vif;
    mon.vif = this.vif;
    gen.drv_next = drv.drv_next;
    gen.sco_next = sco.sco_next;
  endfunction
  
  task pre_test();
    //repeat(2) @(posedge vif.sclk);
    drv.reset();
  endtask
  
  task test();
    fork
      gen.run();
      drv.run();
      mon.run();
      sco.run();
    join_any
  endtask
  
  task post_test();
    wait(gen.done.triggered);
    $finish();
  endtask
  
  task run();
    pre_test();
    test();
    post_test();
  endtask
  
endclass


module tb;
 
  uarttx_if vif();
  uarttx dut (vif.clk, vif.rst, vif.newd, vif.tx_data, vif.tx, vif.donetx);
  
  environment env;

  initial vif.clk <= 1'b0;
  always #10 vif.clk = ~vif.clk;
  
  assign vif.uclk = dut.uclk;
 
  initial begin
    env = new(vif);
    env.gen.count = 5;
    env.run();
  end

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
    #200000;
    $finish();
  end
 
endmodule


