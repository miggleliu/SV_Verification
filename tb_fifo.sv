/* Transaction */
class transaction;
  
  rand bit oper;
  bit wr, rd;
  rand bit [7:0] din;
  bit [7:0] dout;
  bit empty, full;
  
  constraint oper_ctrl{
    oper dist {0 :/ 50, 1 :/ 50};
  }
  
  function transaction copy();
    copy = new();
    copy.oper = this.oper;
    copy.wr = this.wr;
    copy.rd = this.rd;
    copy.din = this.din;
    copy.dout = this.dout;
    copy.empty = this.empty;
    copy.full = this.full;
  endfunction
  
endclass


/* Generator */
class generator;
  
  transaction trans;
  mailbox #(transaction) mbx;
  int count;
  
  event done;
  event next;
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
    trans = new();
  endfunction
  
  task run();
    for (int unsigned i=0; i<count; i++) begin
      assert (trans.randomize()) else $error("Randomization Failed.");
      mbx.put(trans.copy());
      $display("[GEN] : OPER : %0d, iteration: %0d", trans.oper, i);
      @(next); 
    end
    ->done;
  endtask
  
endclass


/* Driver */
class driver;
  
  virtual fifo_if vif;
  transaction trans;
  mailbox #(transaction) mbx;
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
  endfunction
  
  // Reset the DUT
  task reset();
    vif.rst <= 1'b1;
    vif.rd <= 1'b0;
    vif.wr <= 1'b0;
    vif.din <= 0;
    repeat (5) @(posedge vif.clk);
    vif.rst <= 1'b0;
    $display("[DRV] : DUT Reset Done");
    $display("------------------------------------------");
  endtask
  
  // Read
  task read();
    @(posedge vif.clk);
    vif.rst <= 1'b0;
    vif.rd <= 1'b1;
    vif.wr <= 1'b0;
    @(posedge vif.clk);
    vif.rd <= 1'b0;
    $display("[DRV] : DATA READ");
    @(posedge vif.clk);
  endtask
  
  // Write
  task write();
    @(posedge vif.clk);
    vif.rst <= 1'b0;
    vif.rd <= 1'b0;
    vif.wr <= 1'b1;
    vif.din <= trans.din;
    @(posedge vif.clk);
    vif.wr <= 1'b0;
    $display("[DRV] : DATA WRITE  data : %d", vif.din);
    @(posedge vif.clk);
  endtask
  
  task run();
    forever begin
      mbx.get(trans);
      // read
      if (trans.oper == 1'b0) read();
      else write();
    end
  endtask
  
endclass


/* Monitor */
class monitor;
  
  virtual fifo_if vif;
  transaction trans;
  mailbox #(transaction) mbx;
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
    trans = new();
  endfunction
  
  task run();
    forever begin
      repeat(2) @(posedge vif.clk);
      trans.wr = vif.wr;
      trans.rd = vif.rd;
      trans.din = vif.din;
      trans.empty = vif.empty;
      trans.full = vif.full;
      @(posedge vif.clk);
      trans.dout = vif.dout;
      
      mbx.put(trans);
      $display("[MON] : Wr:%0d rd:%0d din:%0d dout:%0d full:%0d empty:%0d", trans.wr, trans.rd, trans.din, trans.dout, trans.full, trans.empty);
      
    end
  endtask

endclass


/* Scoreboard */
class scoreboard;
  transaction trans;
  mailbox #(transaction) mbx;
  bit [7:0] din[$];
  bit [7:0] temp;
  int err = 0;
  event next;
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
  endfunction
  
  function int compare(input bit [7:0] a, input bit [7:0] b);
    if (a == b) begin
      $display("[SCO] : Data Matched!");
      return 0;
    end else begin
      $display("[SCO] : Data Mismatched!");
      return 1;
    end
  endfunction
  
  task run();
    forever begin
      mbx.get(trans);
      
      if (trans.rd == 1'b1) begin
        if (trans.empty == 1'b0) begin
          temp = din.pop_back();
          err += compare(temp, trans.dout);
        end else begin
          $display("[SCO] : FIFO is EMPTY");
        end
      end else if (trans.wr == 1'b1) begin
        if (trans.full == 1'b0) begin
          din.push_front(trans.din);
          $display("[SCO] : data %d is stored into the queue", trans.din);
        end else begin
          $display("[SCO] : FIFO is FULL");
        end
      end 
      
      $display("------------------------------------------");
      
      -> next;
      
    end
  endtask
  
endclass


/* Environment */
class environment;
  
  virtual fifo_if vif;
  
  generator gen;
  driver drv;
  monitor mon;
  scoreboard sco;
  mailbox #(transaction) mbx_g2d;
  mailbox #(transaction) mbx_m2s;
  event next;
  
  function new(virtual fifo_if vif);
    this.vif = vif;
    this.mbx_g2d = new();
    this.mbx_m2s = new();
    gen = new(mbx_g2d);
    drv = new(mbx_g2d);
    mon = new(mbx_m2s);
    sco = new(mbx_m2s);
    drv.vif = this.vif;
    mon.vif = this.vif;
    gen.next = this.next;
    sco.next = this.next;
  endfunction
  
  task pre_test();
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
    $display("------------------------------------------");
    $display("Error count : %d", sco.err);
    $display("------------------------------------------");
    $finish();
  endtask
  
  task run();
    pre_test();
    test();
    post_test();
  endtask
  
endclass



/* TB top */
module tb;
  
  fifo_if vif();
 
  FIFO dut(vif.clk, vif.rst, vif.wr, vif.rd, vif.din, vif.dout, vif.empty, vif.full);
  
  initial vif.clk <= 1'b0;
  always #10 vif.clk <= ~vif.clk;
  
  environment env;
  
  initial begin
    env = new(vif);
    env.gen.count = 100;
    env.run();
  end 
  
  initial begin
    $dumpfile("dump.vcd"); 
    $dumpvars;
  end
  
endmodule





