VERILATOR      ?= verilator
TOP            ?= tb
BUILD_DIR      ?= obj_dir
SIM            := $(BUILD_DIR)/V$(TOP)

SV_SOURCES     := tb.sv hyperram/hyperram.sv
CPP_SOURCES    := hyperram/hyperram_model.cpp controller/hyperbus_controller_model.cpp \
	hyperram/profiles/hyperram_chip_profiles.cpp controller/profiles/controller_chip_profiles.cpp \
	hyperram/profiles/hyperram_profiles.cpp controller/profiles/controller_profiles.cpp

VERILATOR_FLAGS := \
	--binary \
	--timing \
	--sv \
	-Wall \
	-Wno-fatal \
	--top-module $(TOP) \
	--Mdir $(BUILD_DIR)

.PHONY: all build run test clean rebuild test-read-stall test-random test-controller test-controller-zero-latency test-controller-read-stall test-controller-read-timing test-controller-read-error test-controller-geometry test-controller-timing

all: run

build:
	$(VERILATOR) $(VERILATOR_FLAGS) $(SV_SOURCES) $(CPP_SOURCES)

run: build
	./$(SIM)

test: run test-read-stall test-random test-controller test-controller-zero-latency test-controller-read-stall test-controller-read-timing test-controller-read-error test-controller-geometry test-controller-timing

clean:
	rm -rf $(BUILD_DIR)
	rm -f simulation.log wave.vcd wave.fst

rebuild: clean run

test-read-stall:
	$(MAKE) TOP=tb_read_stall BUILD_DIR=obj_dir_read_stall \
		SV_SOURCES="tb_read_stall.sv hyperram/hyperram.sv" run

test-random:
	$(MAKE) TOP=tb_random BUILD_DIR=obj_dir_random \
		SV_SOURCES="tb_random.sv hyperram/hyperram.sv" run

test-controller:
	$(MAKE) TOP=tb_controller BUILD_DIR=obj_dir_controller \
		SV_SOURCES="tb_controller.sv controller/hyperbus_controller.sv hyperram/hyperram.sv" run

test-controller-zero-latency:
	$(MAKE) TOP=tb_controller_zero_latency BUILD_DIR=obj_dir_controller_zero_latency \
		SV_SOURCES="tb_controller_zero_latency.sv controller/hyperbus_controller.sv hyperram/hyperram.sv" run

test-controller-read-stall:
	$(MAKE) TOP=tb_controller_read_stall BUILD_DIR=obj_dir_controller_read_stall \
		SV_SOURCES="tb_controller_read_stall.sv controller/hyperbus_controller.sv hyperram/hyperram.sv" run

test-controller-read-timing:
	$(MAKE) TOP=tb_controller_read_timing BUILD_DIR=obj_dir_controller_read_timing \
		SV_SOURCES="tb_controller_read_timing.sv controller/hyperbus_controller.sv hyperram/hyperram.sv" run

test-controller-read-error:
	$(MAKE) TOP=tb_controller_read_error BUILD_DIR=obj_dir_controller_read_error \
		SV_SOURCES="tb_controller_read_error.sv controller/hyperbus_controller.sv" run

test-controller-geometry:
	$(MAKE) TOP=tb_controller_geometry BUILD_DIR=obj_dir_controller_geometry \
		SV_SOURCES="tb_controller_geometry.sv controller/hyperbus_controller.sv hyperram/hyperram.sv" run

test-controller-timing:
	$(MAKE) TOP=tb_controller_timing BUILD_DIR=obj_dir_controller_timing \
		SV_SOURCES="tb_controller_timing.sv controller/hyperbus_controller.sv hyperram/hyperram.sv" run
