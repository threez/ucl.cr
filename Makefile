.PHONY: spec docs examples

all: clean fmt lint docs spec examples

fmt:
	crystal tool format

spec:
	crystal spec -v

AMEBA=./lib/ameba/bin/ameba

$(AMEBA): $(AMEBA).cr
	crystal build -o $@ $(AMEBA).cr

lint: $(AMEBA)
	$(AMEBA)

docs:
	crystal docs

examples:
	shards build
	./bin/fbsd-pkg

clean:
	rm -rf bin
	rm -rf docs
