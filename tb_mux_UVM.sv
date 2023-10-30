`timescale 1ns/1ps

`include "uvm_macros.svh"
import uvm_pkg::*;


class transaction extends uvm_sequence_item;
  
  rand bit [3:0] a;
  rand bit [3:0] b;
  rand bit [3:0] c;
  rand bit [3:0] d;
  rand bit [1:0] sel;
  bit [3:0] y;
  
  function new(input string name="transaction");
    super.new(name);
  endfunction
  
  `uvm_object_utils_begin(transaction)
  `uvm_field_int(a, UVM_DEFAULT)
  `uvm_field_int(b, UVM_DEFAULT)
  `uvm_field_int(c, UVM_DEFAULT)
  `uvm_field_int(d, UVM_DEFAULT)
  `uvm_field_int(sel, UVM_DEFAULT)
  `uvm_field_int(y, UVM_DEFAULT)
  `uvm_object_utils_end
  
endclass


class generator extends uvm_sequence #(transaction);
  
  `uvm_object_utils(generator)
  
  transaction t;
  
  function new(input string name="generator");
    super.new(name);
  endfunction
  
  virtual task body();
    t = transaction::type_id::create("t");
    repeat(10) begin
      start_item(t);
      t.randomize();
      `uvm_info("GEN", $sformatf("Data sent to driver  a: %0d, b: %0d", t.a, t.b), UVM_NONE);
      finish_item(t);
    end
  endtask
  
endclass


class driver extends uvm_driver #(transaction);
  
  `uvm_component_utils(driver)
  
  function new(input string name="driver", uvm_component parent);
    super.new(name, parent);
  endfunction
  
  transaction tc;
  virtual mux_if aif;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    tc = transaction::type_id::create("tc");
    if (!uvm_config_db #(virtual mux_if)::get(this, "", "aif", aif))
      `uvm_error("DRV", "Unable to access uvm_config_db");
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    forever begin
      seq_item_port.get_next_item(tc);
      aif.a <= tc.a;
      aif.b <= tc.b;
      aif.c <= tc.c;
      aif.d <= tc.d;
      aif.sel <= tc.sel;
      `uvm_info("DRV", $sformatf("Data sent to DUT  a: %0d, b: %0d, c: %0d, d: %0d, sel: %0d", tc.a, tc.b, tc.c, tc.d, tc.sel), UVM_NONE);
      seq_item_port.item_done();
      #10;
    end
  endtask
  
endclass


class monitor extends uvm_monitor;
  
  `uvm_component_utils(monitor)
  
  uvm_analysis_port #(transaction) send;
  
  transaction t;
  virtual mux_if aif;
  
  function new(input string name="monitor", uvm_component parent);
    super.new(name, parent);
    send = new("send", this);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    t = transaction::type_id::create("t");
    if (!uvm_config_db #(virtual mux_if)::get(this, "", "aif", aif))
      `uvm_error("MON", "Cannot access uvm_config_db");
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    forever begin
      #10;
      t.a = aif.a;
      t.b = aif.b;
      t.c = aif.c;
      t.d = aif.d;
      t.sel = aif.sel;
      t.y = aif.y;
      `uvm_info("DRV", $sformatf("Data received from DUT  a: %0d, b: %0d, c: %0d, d: %0d, sel: %0d, y: %0d", t.a, t.b, t.c, t.d, t.sel, t.y), UVM_NONE);
      send.write(t);
    end
  endtask
  
endclass


class scoreboard extends uvm_scoreboard;
  
  `uvm_component_utils(scoreboard)
  
  uvm_analysis_imp #(transaction, scoreboard) recv;
  
  transaction tr;
  
  function new(input string name="scoreboard", uvm_component parent);
    super.new(name, parent);
    recv = new("recv", this);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    tr = transaction::type_id::create("tr");
  endfunction
  
  virtual function void write(input transaction t);
    tr = t;
    `uvm_info("SCO", $sformatf("Data received from MON  a: %0d, b: %0d, c: %0d, d: %0d, sel: %0d, y: %0d", tr.a, tr.b, tr.c, tr.d, tr.sel, tr.y), UVM_NONE);
    if (tr.sel == 2'b00 && tr.y == tr.a || tr.sel == 2'b01 && tr.y == tr.b || tr.sel == 2'b10 && tr.y == tr.c || tr.sel == 2'b11 && tr.y == tr.d) begin
      `uvm_info("SCO", "Test Passed", UVM_NONE);
    end else begin
      `uvm_info("SCO", "Test Failed", UVM_NONE);
    end
  endfunction
  
endclass
    

class agent extends uvm_agent;
  
  `uvm_component_utils(agent)
  
  driver d;
  monitor m;
  uvm_sequencer #(transaction) seqr;
  
  function new(input string name="agent", uvm_component parent);
    super.new(name, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    d = driver::type_id::create("d", this);
    m = monitor::type_id::create("m", this);
    seqr = uvm_sequencer #(transaction)::type_id::create("seqr", this);
  endfunction
  
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    d.seq_item_port.connect(seqr.seq_item_export);
  endfunction
  
endclass


class env extends uvm_env;
  
  `uvm_component_utils(env)
  
  agent a;
  scoreboard s;
  
  function new(input string name="env", uvm_component parent);
    super.new(name, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    a = agent::type_id::create("a", this);
    s = scoreboard::type_id::create("s", this);
  endfunction
  
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    a.m.send.connect(s.recv);
  endfunction
  
endclass


class test extends uvm_test;
  
  `uvm_component_utils(test)
  
  env e;
  generator g;
  
  function new(input string name="test", uvm_component parent);
    super.new(name, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    e = env::type_id::create("e", this);
    g = generator::type_id::create("g", this);
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    g.start(e.a.seqr);
    #50;
    phase.drop_objection(this);
  endtask
  
endclass


module add_tb();
  
  mux_if aif();
  mux dut(aif.a, aif.b, aif.c, aif.d, aif.sel, aif.y);
  
  initial begin
    uvm_config_db #(virtual mux_if)::set(null, "uvm_test_top.e.a*", "aif", aif);
    run_test("test");
  end
  
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end
  
endmodule


