.PHONY: all clean

# You may need to set these to the correct name or path e.g. llvm-config-14
LLVMCONFIG=llvm-config
CXX = clang++

CXXFLAGS = -g -std=c++14 -Wall -Wno-deprecated-register \
           -Wno-unneeded-internal-declaration \
           -Wno-unused-function

all:
	flex -o p1.lex.cpp p1.lex
	bison -d -o p1.y.cpp p1.y
	$(CXX) $(CXXFLAGS) -c -o p1.lex.o p1.lex.cpp `$(LLVMCONFIG) --cppflags` -g
	$(CXX) $(CXXFLAGS) -c -o p1.y.o p1.y.cpp `$(LLVMCONFIG) --cppflags` -g
	$(CXX) $(CXXFLAGS) -c -o p1.o p1.cpp `$(LLVMCONFIG) --cppflags` -g
	$(CXX) $(CXXFLAGS) -o p1 p1.o p1.y.o p1.lex.o `$(LLVMCONFIG) --ldflags --libs --system-libs` -g

clean:
	rm -Rf p1 *.o p1.y.cpp p1.y.hpp p1.lex.cpp
