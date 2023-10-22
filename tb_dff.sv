/////////////////////////////////
class transaction;
  
  rand logic din;
  logic dout;
  
  function transaction copy();
    copy = new();
    copy.din = this.din;
    copy.dout = this.dout;
  endfunction
  
  function display(string block);
    $display("[%0s] : transaction displayed : din = %0d, dout = %0d.", block, this.din, this.dout);
  endfunction
  
endclass


/////////////////////////////////
class generator;
  
  transaction trans;
  mailbox #(transaction) mbx;
  mailbox #(transaction) mbx_ref;
  int unsigned count;
  event sco_ready;
  event done;
  
  function new(mailbox #(transaction) mbx, mailbox #(transaction) mbx_ref);
    this.mbx = mbx;
    this.mbx_ref = mbx_ref;
    this.trans = new();
  endfunction
  
  task run();
    for (int unsigned i=0; i<count; i++) begin
      assert(trans.randomize()) else $error("Randomization Failed!");
      mbx.put(trans.copy());
      mbx_ref.put(trans.copy());
      trans.display("GEN");
      @(sco_ready);
    end
    -> done;
  endtask
    

endclass


/////////////////////////////////
class driver;
  
  virtual dff_if vif;
  transaction trans;
  mailbox #(transaction) mbx;
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
  endfunction
  
  task reset();
    #5;
    vif.rst <= 1'b1;
    repeat(5) @(posedge vif.clk);
    vif.rst <= 1'b0;
  endtask
  
  task run();
    forever begin
      mbx.get(trans);
      trans.display("DRV");
      vif.din <= trans.din;
      @(posedge vif.clk);
      @(posedge vif.clk);
    end
  endtask
  
endclass


/////////////////////////////////
class monitor;
  
  virtual dff_if vif;
  transaction trans;
  mailbox #(transaction) mbx;
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
  endfunction
  
  task run();
    trans = new();
    forever begin
      @(posedge vif.clk);
      @(posedge vif.clk);
      trans.dout = vif.dout;
      mbx.put(trans);
      trans.display("MON");
    end
  endtask
  
endclass


/////////////////////////////////
class scoreboard;
  
  transaction trans;
  transaction trans_ref;
  mailbox #(transaction) mbx;
  mailbox #(transaction) mbx_ref;
  event sco_ready;
  
  function new(mailbox #(transaction) mbx, mailbox #(transaction) mbx_ref);
    this.mbx = mbx;
    this.mbx_ref = mbx_ref;
  endfunction
  
  function compare();
    if (trans_ref.din == trans.dout)
      $display("Data Matched!");
    else
      $display("Data Mismatched!");
  endfunction
  
  task run();
    forever begin
      mbx.get(trans);
      mbx_ref.get(trans_ref);
      trans.display("SCO");
      trans_ref.display("REF");
      compare();
      -> sco_ready;
    end
  endtask
  
endclass


/////////////////////////////////
class environment;
  
  mailbox #(transaction) mbx_in_path;
  mailbox #(transaction) mbx_ref;
  mailbox #(transaction) mbx_out_path;
  generator gen;
  driver drv;
  monitor mon;
  scoreboard sco;
  virtual dff_if vif;
  
  function new(virtual dff_if vif);
    this.vif = vif;
    mbx_ref = new();
    mbx_in_path = new();
    mbx_out_path = new();
    gen = new(mbx_in_path, mbx_ref);
    drv = new(mbx_in_path);
    mon = new(mbx_out_path);
    sco = new(mbx_out_path, mbx_ref);
    sco.sco_ready = gen.sco_ready;
    drv.vif = this.vif;
    mon.vif = this.vif;
  endfunction
  
  task pre_main();
    drv.reset();
  endtask
  
  task main();
    fork
      gen.run();
      drv.run();
      mon.run();
      sco.run();
    join_any
  endtask
  
  task post_main();
    wait(gen.done.triggered);
    $finish();
  endtask
  
  task run();
    pre_main();
    main();
    post_main();
  endtask
  
endclass


/////////////////////////////////
module tb;
  
  environment env;
  dff_if vif();
  
  dff dut(vif);
  
  initial begin
    env = new(vif);
    env.gen.count = 20;
    env.run();
  end
  
  initial begin
    vif.clk <= 1'b0;
  end
  
  always #10 vif.clk <= ~vif.clk;
  
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end
  
endmodule
