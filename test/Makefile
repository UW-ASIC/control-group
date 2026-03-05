# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# Pin the default goal before cocotb's Makefile.sim can override it
.DEFAULT_GOAL := all

# defaults
SIM ?= icarus
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../src

PROJECT_SOURCES = deserializer.v req_queue.v aes_fsm.v sha_fsm.v bus_arbiter.v comp_queue.v serializer.v control_top.v

ifneq ($(GATES),yes)

# RTL simulation:
SIM_BUILD = sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))

else

# Gate level simulation:
SIM_BUILD = sim_build/gl
COMPILE_ARGS += -DGL_TEST
COMPILE_ARGS += -DFUNCTIONAL
COMPILE_ARGS += -DUSE_POWER_PINS
COMPILE_ARGS += -DSIM
COMPILE_ARGS += -DUNIT_DELAY=\#1
VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v
VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v

# this gets copied in by the GDS action workflow
VERILOG_SOURCES += $(PWD)/gate_level_netlist.v

endif

# Allow sharing configuration between design and testbench via `include`:
COMPILE_ARGS += -I$(SRC_DIR)

.PHONY: all test-aes-fsm test-sha-fsm test-bus-arbiter test-deserializer test-req-queue test-comp-queue test-serializer

all: test-aes-fsm test-sha-fsm test-bus-arbiter test-deserializer test-req-queue test-comp-queue test-serializer

test-aes-fsm:
	$(MAKE) clean
	$(MAKE) sim \
		MODULE=test_aes_fsm \
		TOPLEVEL=aes_fsm_tb \
		VERILOG_SOURCES="$(PWD)/aes_fsm_tb.v $(SRC_DIR)/aes_fsm.v" \
		SIM_BUILD=sim_build/aes_fsm \
		COCOTB_RESULTS_FILE=results_aes_fsm.xml

test-sha-fsm:
	$(MAKE) clean
	$(MAKE) sim \
		MODULE=test_sha_fsm \
		TOPLEVEL=sha_fsm_tb \
		VERILOG_SOURCES="$(PWD)/sha_fsm_tb.v $(SRC_DIR)/sha_fsm.v" \
		SIM_BUILD=sim_build/sha_fsm \
		COCOTB_RESULTS_FILE=results_sha_fsm.xml

test-bus-arbiter:
	$(MAKE) clean
	$(MAKE) sim \
		MODULE=test_bus_arbiter \
		TOPLEVEL=bus_arbiter_tb \
		VERILOG_SOURCES="$(PWD)/bus_arbiter_tb.v $(SRC_DIR)/bus_arbiter.v" \
		SIM_BUILD=sim_build/bus_arbiter \
		COCOTB_RESULTS_FILE=results_bus_arbiter.xml

test-deserializer:
	$(MAKE) clean
	$(MAKE) sim \
		MODULE=test_deserializer \
		TOPLEVEL=deserializer_tb \
		VERILOG_SOURCES="$(PWD)/deserializer_tb.v $(SRC_DIR)/deserializer.v" \
		SIM_BUILD=sim_build/deserializer \
		COCOTB_RESULTS_FILE=results_deserializer.xml

test-req-queue:
	$(MAKE) clean
	$(MAKE) sim \
		MODULE=test_req_queue \
		TOPLEVEL=req_queue_tb \
		VERILOG_SOURCES="$(PWD)/req_queue_tb.v $(SRC_DIR)/req_queue.v" \
		SIM_BUILD=sim_build/req_queue \
		COCOTB_RESULTS_FILE=results_req_queue.xml

test-comp-queue:
	$(MAKE) clean
	$(MAKE) sim \
		MODULE=test_comp_queue \
		TOPLEVEL=comp_queue_tb \
		VERILOG_SOURCES="$(PWD)/comp_queue_tb.v $(SRC_DIR)/comp_queue.v" \
		SIM_BUILD=sim_build/comp_queue \
		COCOTB_RESULTS_FILE=results_comp_queue.xml

test-serializer:
	$(MAKE) clean
	$(MAKE) sim \
		MODULE=test_serializer \
		TOPLEVEL=serializer_tb \
		VERILOG_SOURCES="$(PWD)/serializer_tb.v $(SRC_DIR)/serializer.v" \
		SIM_BUILD=sim_build/serializer \
		COCOTB_RESULTS_FILE=results_serializer.xml

.PHONY: clean
clean::
	rm -rf sim_build* results*.xml

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim
