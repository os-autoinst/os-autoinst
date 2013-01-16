.PHONY: clean install

CXX := c++
DESTDIR := 
PREFIX := usr/local

lib_targets = libtinycv.so tinycv.so

.SECONDARY: $(lib_targets)

tinycv.so:

%_wrap.cxx: %.i
	swig -perl5 -c++ $^

%.pm: %.i %_wrap.cxx

%_wrap.o: %_wrap.cxx
	$(CXX) -O3 -c -fPIC $^ `perl -MExtUtils::Embed -e ccopts`

lib%.so: %.o
	$(CXX) -shared `pkg-config --libs opencv` -o $@ $^


%.so: %_wrap.o lib%.so
	$(CXX) -shared -ltinycv -Xlinker -L $(PWD) -Xlinker -rpath $(PWD) -o $@ $^
	#$(CXX) -shared -ltinycv -Xlinker -L . -Xlinker -rpath . -o $@ $^


%.o: %.cc
	$(CXX) -O3 -fPIC `pkg-config --cflags opencv` -o $@ -c $^



clean:
	rm -f $(lib_targets)
	rm -f *.o
	rm -f *_wrap.cxx
	rm -f *.pm

#install: $(bin_targets)
#	install -m755 -s -t $(DESTDIR)/$(PREFIX)/bin/ $^
