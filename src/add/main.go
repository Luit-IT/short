package main

import (
	"crypto/sha1"
	"encoding/base64"
	"flag"
	"fmt"
	"os"
)

func usage() {
	fmt.Fprintf(os.Stderr, "Usage of %s: \n", os.Args[0])
	fmt.Fprintf(os.Stderr, "  %s url\n", os.Args[0])
}

func main() {
	flag.Usage = usage
	flag.Parse()

	if flag.NArg() != 1 {
		usage()
		os.Exit(1)
	}

	b64 := base64.NewEncoder(base64.URLEncoding, os.Stdout)
	s := sha1.New()
	fmt.Fprintf(s, "%s", flag.Arg(0))
	fmt.Fprintf(b64, "%s", s.Sum())
	b64.Close()
	fmt.Fprintf(os.Stdout, "\n")
}
