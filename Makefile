.PHONY: test bench-simple clean update-golang-test fuzz fuzz-json

golang.version ?= 1.15.2
golang.tmp.root := /tmp/golang$(golang.version)
golang.tmp.json.root := $(golang.tmp.root)/go-go$(golang.version)/src/encoding/json
golang.test.files := $(wildcard json/golang_*_test.go)
benchstat := ${GOPATH}/bin/benchstat
go-fuzz := ${GOPATH}/bin/go-fuzz
go-fuzz-build := ${GOPATH}/bin/go-fuzz-build
go-fuzz-corpus := ${GOPATH}/src/github.com/dvyukov/go-fuzz-corpus
go-fuzz-dep := ${GOPATH}/src/github.com/dvyukov/go-fuzz/go-fuzz-dep

test:
	go test -v -cover ./ascii
	go test -v -cover ./json
	go test -v -cover ./proto
	go test -v -cover -tags go1.15 ./json
	go test -v -cover ./iso8601
	go run ./json/bugs/issue11/main.go
	go run ./json/bugs/issue18/main.go

$(benchstat):
	GO111MODULE=off go get -u golang.org/x/perf/cmd/benchstat

# This compares segmentio/encoding/json to the standard golang encoding/json;
# for more in-depth benchmarks, see the `benchmarks` directory.
bench-simple: $(benchcmp)
	@go test -v -run '^$$' -bench '(Marshal|Unmarshal)$$/codeResponse' -benchmem -cpu 1 -count 5 ./json -package encoding/json | tee encoding-json.txt
	@go test -v -run '^$$' -bench '(Marshal|Unmarshal)$$/codeResponse' -benchmem -cpu 1 -count 5 ./json -package github.com/json-iterator/go | tee json-iterator.txt
	@go test -v -run '^$$' -bench '(Marshal|Unmarshal)$$/codeResponse' -benchmem -cpu 1 -count 5 ./json | tee segmentio-encoding-json.txt
	benchstat encoding-json.txt segmentio-encoding-json.txt
	benchstat json-iterator.txt segmentio-encoding-json.txt

bench-master: $(benchstat)
	git stash
	git checkout master
	@go test -v -run '^$$' -bench /codeResponse -benchmem -cpu 1 ./json -count 5 | tee /tmp/segmentio-encoding-json-master.txt
	git checkout -
	git stash pop
	@go test -v -run '^$$' -bench /codeResponse -benchmem -cpu 1 ./json -count 5 | tee /tmp/segmentio-encoding-json.txt
	benchstat /tmp/segmentio-encoding-json-master.txt /tmp/segmentio-encoding-json.txt

update-golang-test: $(golang.test.files)
	@echo "updated golang tests to $(golang.version)"

json/golang_%_test.go: $(golang.tmp.json.root)/%_test.go $(golang.tmp.json.root)
	@echo "updating $@ with $<"
	cp $< $@
	sed -i '' -E '/(import)?[ \t]*"internal\/.*".*/d' $@

$(golang.tmp.json.root): $(golang.tmp.root)
	curl -L "https://github.com/golang/go/archive/go${golang.version}.tar.gz" | tar xz -C "$</"

$(golang.tmp.root):
	mkdir -p "$@"

$(go-fuzz):
	GO111MODULE=off go install github.com/dvyukov/go-fuzz/go-fuzz

$(go-fuzz-build):
	GO111MODULE=off go install github.com/dvyukov/go-fuzz/go-fuzz-build

$(go-fuzz-corpus):
	GO111MODULE=off go get github.com/dvyukov/go-fuzz-corpus

$(go-fuzz-dep):
	GO111MODULE=off go get github.com/dvyukov/go-fuzz/go-fuzz-dep

json/fuzz/corpus: $(go-fuzz-corpus)
	cp -r $(go-fuzz-corpus)/json/corpus json/fuzz/corpus

json/fuzz/json-fuzz.zip: $(go-fuzz-build) $(go-fuzz-corpus) $(go-fuzz-dep) $(wildcard ./json/fuzz/corpus/*)
	cd json/fuzz && GO111MODULE=off go-fuzz-build -o json-fuzz.zip

fuzz: fuzz-json

fuzz-json: $(go-fuzz) $(wildcard json/fuzz/*.go) json/fuzz/json-fuzz.zip
	cd json/fuzz && GO111MODULE=off go-fuzz -bin json-fuzz.zip

clean:
	rm -rf $(golang.tmp.root) json/fuzz/{crashers,corpus,suppressions,json-fuzz.zip} *json.txt
