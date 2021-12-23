SOURCE = 

INCDIR = 

OUTDIR = objects
BINDIR = bin
VPATH  = source

BINARY = ParseFixStream

CC     = gcc
CXX    = g++

vpath %.d           $(OUTDIR)
vpath %.o           $(OUTDIR)
vpath $(BINARY)     $(BINDIR)

BIN_OBJECTS=$(patsubst %.c,%.o,$(patsubst %.cpp,%.o,$(SOURCE)))
BIN_DEPENDS=$(patsubst %.c,%.d,$(patsubst %.cpp,%.d,$(SOURCE)))

CFLAGS   = $(WOPT) $(EXTRAFLAGS) $(OPT) $(addprefix -I , $(INCDIR))
CXXFLAGS = $(WOPT) $(EXTRAFLAGS) $(OPT) $(addprefix -I , $(INCDIR))

ifeq ($(INCLUDEDEP),1)
    -include $(addprefix $(OUTDIR)/, $(BIN_DEPENDS))
endif

all:
	$(MAKE) INCLUDEDEP=0 .depend
	$(MAKE) INCLUDEDEP=1 $(BINARY)

$(BINARY): $(BINDIR) $(BIN_OBJECTS)
ifneq ($(INCLUDEDEP),1)
	$(MAKE) INCLUDEDEP=1 $(BINARY)
else
	g++ -o $(BINDIR)/$@ $(addprefix $(OUTDIR)/,$(BIN_OBJECTS))
endif

clean:
	rm $(OUTDIR)/* $(BINDIR)/*

$(BINDIR) $(OUTDIR):
	mkdir $@

.depend:$(BINDIR) $(OUTDIR) $(BIN_DEPENDS)

# Generate object files
%.o:%.cpp
	$(CXX) $(CXXFLAGS) -c -o $(OUTDIR)/$@ $<
%.o:%.c
	$(CXX) $(CFLAGS) -c -o $(OUTDIR)/$@ $<
# Generate the depenedecies
%.d:%.cpp
	$(CXX) -MM $(CXXFLAGS) $< > $(OUTDIR)/$@
%.d:%.c
	$(CC) -MM $(CFLAGS) $< > $(OUTDIR)/$@
