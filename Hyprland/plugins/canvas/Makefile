# &desc: "build recipe for the canvas plugin, mirrors the standard Hyprland out-of-tree plugin convention"
PLUGIN_NAME = canvas

CXX       = g++
CXXFLAGS  = -shared -fPIC -std=c++2b -O2 -Wall -Wextra
CXXFLAGS += $(shell pkg-config --cflags hyprland pixman-1 libdrm)

SRC = main.cpp HyprlandHooks.cpp CanvasState.cpp
OUT = $(PLUGIN_NAME).so

all: $(OUT)

$(OUT): $(SRC) CanvasState.hpp HyprlandHooks.hpp
	$(CXX) $(CXXFLAGS) $(SRC) -o $(OUT)

install: $(OUT)
	hyprctl plugin load $(PWD)/$(OUT)

unload:
	hyprctl plugin unload $(PWD)/$(OUT)

# bypasses the dynamic linker's dlopen cache while iterating on the plugin
reload: $(OUT)
	-hyprctl plugin unload $(PWD)/$(OUT)
	-hyprctl plugin unload /tmp/$(PLUGIN_NAME)-live.so
	cp $(PWD)/$(OUT) /tmp/$(PLUGIN_NAME)-live.so
	hyprctl plugin load /tmp/$(PLUGIN_NAME)-live.so

clean:
	rm -f $(OUT)

.PHONY: all install unload reload clean
