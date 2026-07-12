package main

import (
	"fmt"
	"io"
	"os"
)

// version is injected at build time via -ldflags "-X main.version=...".
// It defaults to "dev" for a plain `go build`. Under Nix it is the commit;
// at release it will be the verseal-computed semver.
var version = "dev"

func main() {
	if err := run(os.Args, os.Stdout, os.Stderr); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(args []string, stdout, stderr io.Writer) error {
	_ = stderr // reserved for command output as the CLI grows
	line := "verseal " + version
	if len(args) > 1 {
		switch args[1] {
		case "version", "--version", "-v":
			line = version
		}
	}
	_, err := fmt.Fprintln(stdout, line)
	return err
}
