package main

import (
	"bytes"
	"strings"
	"testing"
)

// Just to prove testing works
func TestRun(t *testing.T) {
	cases := []struct {
		name string
		args []string
		want string
	}{
		{"no args", []string{"verseal"}, "verseal dev"},
		{"version", []string{"verseal", "version"}, "dev"},
		{"--version", []string{"verseal", "--version"}, "dev"},
		{"-v", []string{"verseal", "-v"}, "dev"},
		{"other arg", []string{"verseal", "status"}, "verseal dev"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			var stdout, stderr bytes.Buffer
			if err := run(c.args, &stdout, &stderr); err != nil {
				t.Fatalf("run returned error: %v", err)
			}
			if got := strings.TrimSpace(stdout.String()); got != c.want {
				t.Errorf("stdout = %q, want %q", got, c.want)
			}
			if stderr.Len() != 0 {
				t.Errorf("stderr = %q, want empty", stderr.String())
			}
		})
	}
}
