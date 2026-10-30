# Metro Management System - Linux Makefile
# Targets: all, run, test, gtest, gcov, cppcheck, misra, valgrind, helgrind, clean

CC       = gcc
CXX      = g++
GCOV     ?= gcov
GCOVR    ?= gcovr
CPPCHECK ?= cppcheck
VALGRIND ?= valgrind
MAKE     ?= make

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

CPPFLAGS := -Iinclude
CFLAGS   ?= -std=c11 -Wall -Wextra -Wpedantic -g
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Wpedantic -O0 -g
THREADS  := -pthread
LDLIBS   := -lm

SRC_DIR   := src
TEST_DIR  := test
BUILD_DIR := build
DATA_DIR  := data

APP_SOURCES := $(SRC_DIR)/main.c \
               $(SRC_DIR)/bst.c \
               $(SRC_DIR)/storage.c \
               $(SRC_DIR)/auth.c \
               $(SRC_DIR)/audit_log.c \
               $(SRC_DIR)/station_validation_threads.c

CORE_SOURCES := $(SRC_DIR)/bst.c \
                $(SRC_DIR)/storage.c \
                $(SRC_DIR)/auth.c \
                $(SRC_DIR)/audit_log.c \
                $(SRC_DIR)/station_validation_threads.c

APP := $(BUILD_DIR)/metro

C_TESTS := $(BUILD_DIR)/test_bst \
           $(BUILD_DIR)/test_storage \
           $(BUILD_DIR)/test_auth \
           $(BUILD_DIR)/test_audit_log

GTEST_DIR := $(BUILD_DIR)/gtest
GTEST_WORK := $(GTEST_DIR)/work
GTEST_BIN := $(GTEST_DIR)/metro_gtest
GTEST_OBJECTS := $(GTEST_DIR)/main_test.o \
                 $(GTEST_DIR)/bst.o \
                 $(GTEST_DIR)/storage.o \
                 $(GTEST_DIR)/auth.o \
                 $(GTEST_DIR)/audit_log.o \
                 $(GTEST_DIR)/station_validation_threads.o
GTEST_TEST_OBJECT := $(GTEST_DIR)/test_metro_gtest.o
GTEST_COVERAGE_SOURCES := main_test bst storage auth audit_log station_validation_threads

.PHONY: all run test gtest gcov coverage cppcheck misra valgrind helgrind clean help check-tools

all: $(APP)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(APP): $(APP_SOURCES) $(wildcard include/*.h) | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(CPPFLAGS) $(APP_SOURCES) $(THREADS) $(LDLIBS) -o $@

run: $(APP)
	./$(APP)

# Build each existing C test using the modules it exercises.
$(BUILD_DIR)/test_bst: $(TEST_DIR)/test_bst.c $(SRC_DIR)/bst.c $(wildcard include/*.h) | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(CPPFLAGS) $< $(SRC_DIR)/bst.c $(THREADS) $(LDLIBS) -o $@

$(BUILD_DIR)/test_storage: $(TEST_DIR)/test_storage.c $(SRC_DIR)/bst.c $(SRC_DIR)/storage.c $(wildcard include/*.h) | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(CPPFLAGS) $< $(SRC_DIR)/bst.c $(SRC_DIR)/storage.c $(THREADS) $(LDLIBS) -o $@

$(BUILD_DIR)/test_auth: $(TEST_DIR)/test_auth.c $(SRC_DIR)/auth.c $(wildcard include/*.h) | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(CPPFLAGS) $< $(SRC_DIR)/auth.c $(THREADS) $(LDLIBS) -o $@

$(BUILD_DIR)/test_audit_log: $(TEST_DIR)/test_audit_log.c $(SRC_DIR)/audit_log.c $(wildcard include/*.h) | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(CPPFLAGS) $< $(SRC_DIR)/audit_log.c $(THREADS) $(LDLIBS) -o $@

test: $(C_TESTS)
	@set -eu; \
	mkdir -p $(BUILD_DIR)/test-work/data; \
	cp $(DATA_DIR)/stations.csv $(BUILD_DIR)/test-work/data/stations.csv; \
	cp $(DATA_DIR)/users.csv $(BUILD_DIR)/test-work/data/users.csv; \
	cp $(DATA_DIR)/audit.log $(BUILD_DIR)/test-work/data/audit.log; \
	cd $(BUILD_DIR)/test-work; \
	../test_bst; \
	../test_storage; \
	../test_auth; \
	../test_audit_log

# GoogleTest suite: compile C files as C, then link the C++ test runner.
$(GTEST_DIR):
	mkdir -p $(GTEST_DIR)

$(GTEST_DIR)/%.o: $(SRC_DIR)/%.c $(wildcard include/*.h) | $(GTEST_DIR)
	$(CC) -std=c11 -Wall -Wextra -Wpedantic -Wshadow -Wconversion -O0 -g --coverage $(CPPFLAGS) $(THREADS) -c $< -o $@

$(GTEST_DIR)/main_test.o: $(SRC_DIR)/main.c $(wildcard include/*.h) | $(GTEST_DIR)
	$(CC) -std=c11 -Wall -Wextra -Wpedantic -Wshadow -Wconversion -O0 -g --coverage $(CPPFLAGS) $(THREADS) -Dmain=metro_app_main -c $< -o $@

$(GTEST_TEST_OBJECT): test_gtest/test_metro_gtest.cpp $(wildcard include/*.h) | $(GTEST_DIR)
	$(CXX) -std=c++17 -Wall -Wextra -Wpedantic -O0 -g --coverage $(CPPFLAGS) $(THREADS) -c $< -o $@

$(GTEST_BIN): $(GTEST_TEST_OBJECT) $(GTEST_OBJECTS)
	$(CXX) $(CXXFLAGS) --coverage $^ -lgtest $(THREADS) $(LDLIBS) -lstdc++fs -o $@

# Use a separate working directory/data fixture so tests cannot overwrite project data/.
gtest: $(GTEST_BIN)
	@mkdir -p $(GTEST_WORK)/data
	@cp $(DATA_DIR)/stations.csv $(GTEST_WORK)/data/stations.csv
	@cp $(DATA_DIR)/users.csv $(GTEST_WORK)/data/users.csv
	@cp $(DATA_DIR)/audit.log $(GTEST_WORK)/data/audit.log
	@cd $(GTEST_WORK) && ../metro_gtest

gcov: gtest
	@echo '========== GCOV REPORT =========='
	@cd $(GTEST_DIR) && $(GCOV) -b -c $(addsuffix .gcno,$(GTEST_COVERAGE_SOURCES))
	@if command -v $(GCOVR) >/dev/null 2>&1; then \
		echo '========== AGGREGATE COVERAGE =========='; \
		$(GCOVR) --root . --filter '.*(main|bst|storage|auth|audit_log|station_validation_threads)\.c$$' --print-summary --branches; \
	else \
		echo 'gcovr not found; install it with your approved Linux package/Python method to enable aggregate coverage.'; \
	fi

coverage: gcov

cppcheck:
	$(CPPCHECK) --enable=warning,style,performance,portability --language=c --std=c11 $(CPPFLAGS) $(SRC_DIR) include $(TEST_DIR)

misra:
	$(CPPCHECK) --addon=/usr/share/cppcheck/addons/misra.py --language=c --std=c11 $(CPPFLAGS) $(SRC_DIR) include $(TEST_DIR) 2>&1 | tee misra_report.txt

valgrind: $(APP)
	$(VALGRIND) --leak-check=full --show-leak-kinds=all --track-origins=yes ./$(APP)

helgrind: $(APP)
	$(VALGRIND) --tool=helgrind --history-level=full ./$(APP)

check-tools:
	@for tool in $(CC) $(CXX) $(GCOV) $(CPPCHECK) $(VALGRIND); do \
		if command -v $$tool >/dev/null 2>&1; then printf 'FOUND: %s\n' "$$tool"; \
		else printf 'MISSING: %s\n' "$$tool"; fi; \
	done
	@if printf '#include <gtest/gtest.h>\nint main(){return 0;}\n' | $(CXX) -x c++ -std=c++17 - -lgtest -pthread -o /tmp/metro_gtest_check >/dev/null 2>&1; then \
		echo 'FOUND: GoogleTest headers/library'; rm -f /tmp/metro_gtest_check; \
	else echo 'MISSING: GoogleTest headers/library'; fi

clean:
	rm -rf $(BUILD_DIR) *.gcda *.gcno *.gcov misra_report.txt

help:
	@echo 'Metro Management System Makefile targets:'
	@echo '  make             Build the application'
	@echo '  make run         Build and run the application'
	@echo '  make test        Build and run the existing C tests in an isolated working directory'
	@echo '  make gtest       Build and run GoogleTest'
	@echo '  make gcov        Run GoogleTest and generate GCOV/optional GCOVR reports'
	@echo '  make cppcheck    Run Cppcheck static analysis'
	@echo '  make misra       Run Cppcheck MISRA addon and save misra_report.txt'
	@echo '  make valgrind    Run the application under Valgrind Memcheck'
	@echo '  make helgrind    Run the application under Valgrind Helgrind'
	@echo '  make check-tools Check whether common tools are installed'
	@echo '  make clean       Remove generated build and coverage files'
