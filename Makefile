TARGET		= ex
CXXFLAGS += -O0 -g -std=c++1z
LFLAGS   += -framework Cocoa -framework Metal -framework MetalKit\
						-framework QuartzCore
$(TARGET): main.mm
	$(CXX) $(CXXFLAGS) main.mm $(LFLAGS) -o $(TARGET)
clean:
	-$(RM) -rf $(TARGET).dSYM/ $(TARGET)
