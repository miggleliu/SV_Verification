// Code your testbench here
// or browse Examples
class transaction;
  
  bit newd;
  rand bit [11:0] din; 
  bit cs;
  bit mosi;
  bit [11:0] dout;
  
  function transaction copy();
    copy = new();
    copy.newd = this.newd;
    copy.din = this.din;
    copy.cs = this.cs;
    copy.mosi = this.mosi;
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
      @(drv_next);
      @(sco_next);
    end
    ->done;
  endtask
  
endclass


interface spi_master_if;
  logic clk, newd,rst;
  logic [11:0] din; 
  logic sclk,cs,mosi;
endinterface


class driver;
  
  virtual spi_master_if vif;
  transaction trans;
  mailbox #(transaction) mbx;
  mailbox #(bit [11:0]) mbx_din;
  event drv_next;
  
  function new(mailbox #(transaction) mbx, mailbox #(bit [11:0]) mbx_din);
    this.mbx = mbx;
    this.mbx_din = mbx_din;
  endfunction
  
  task reset();
    vif.rst <= 1'b1;
    vif.newd <= 1'b0;
    vif.din <= 12'b0;
    repeat(5) @(posedge vif.clk);
    vif.rst <= 1'b0;
  endtask
  
  task run();
    forever begin
      mbx.get(trans);
      vif.din <= trans.din;
      vif.newd <= 1'b1;
      mbx_din.put(trans.din);
      $display("[DRV]");
      //@(posedge vif.sclk);
      //vif.newd <= 1'b0;
      ->drv_next;
    end
  endtask
  
endclass


class monitor;
  
  virtual spi_master_if vif;
  transaction trans;
  mailbox #(transaction) mbx;
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
    trans = new();
  endfunction
  
  task run();
    forever begin
      @(negedge vif.cs);
      for (int i=0; i<12; i++) begin
        @(negedge vif.sclk);
        trans.mosi = vif.mosi;
        trans.dout = {trans.mosi, trans.dout[11:1]};
      end
      mbx.put(trans);
      $display("[MON]");
    end
  endtask
  
endclass


class scoreboard;
  
  transaction trans;
  bit [11:0] din;
  mailbox #(transaction) mbx;
  mailbox #(bit [11:0]) mbx_din;
  event sco_next;
  
  function new(mailbox #(transaction) mbx, mailbox #(bit [11:0]) mbx_din);
    this.mbx = mbx;
    this.mbx_din = mbx_din;
  endfunction
  
  task run();
    forever begin
      mbx.get(trans);
      mbx_din.get(din);
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
  
  virtual spi_master_if vif;
  generator gen;
  driver drv;
  monitor mon;
  scoreboard sco;
  mailbox #(transaction) mbx_g2d;
  mailbox #(transaction) mbx_m2s;
  mailbox #(bit [11:0]) mbx_din;
  
  function new(virtual spi_master_if vif);
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
 
  spi_master_if vif();
  spi_master dut (vif.clk, vif.newd, vif.rst, vif.din, vif.sclk, vif.cs, vif.mosi);
  
  environment env;

  initial vif.clk <= 1'b0;
  always #10 vif.clk = ~vif.clk;
 
  initial begin
    env = new(vif);
    env.gen.count = 5;
    env.run();
  end

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end
 
endmodule


