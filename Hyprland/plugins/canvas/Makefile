# &desc: "Build rules for the canvas Hyprland plugin -- plain Makefile, no CMake (see DESIGN.md)."

# --no-gnu-unique avoids STB_GNU_UNIQUE symbol-binding issues across
# dlopen'd plugins sharing inline globals with the host process (Hyprland's
# own official plugins apply this same flag for g++, e.g. hyprland-plugins'
# borders-plus-plus).
ifeq ($(CXX),g++)
    EXTRA_FLAGS = --no-gnu-unique
else
    EXTRA_FLAGS =
endif

CXXFLAGS ?= -O2
CXXFLAGS += -shared -fPIC -std=c++2b

SRC = src/main.cpp \
      src/hypr/VersionGuard.cpp src/hypr/RenderHook.cpp src/hypr/Dispatchers.cpp src/hypr/WindowPlacement.cpp \
      src/canvas/CanvasState.cpp src/canvas/Transform.cpp
OUT = canvas.so

# Nix's stdenv.mkDerivation exports $out for the sandboxed build; a
# standalone `make install` outside Nix falls back to /usr/local.
out ?= /usr/local

all: $(OUT)

$(OUT): $(SRC)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) $(EXTRA_FLAGS) $(SRC) -o $(OUT) `pkg-config --cflags hyprland lua`

install: $(OUT)
	mkdir -p $(out)/lib
	cp $(OUT) $(out)/lib/

clean:
	rm -f $(OUT)

.PHONY: all install clean
