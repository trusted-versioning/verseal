//go:build unit

package main

import (
	"bytes"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_unit_run(t *testing.T) {
	tests := []struct {
		name     string
		args     []string
		expected string
	}{
		{"no args prints name and version", []string{"verseal"}, "verseal dev"},
		{"version subcommand prints the bare version", []string{"verseal", "version"}, "dev"},
		{"--version flag prints the bare version", []string{"verseal", "--version"}, "dev"},
		{"-v flag prints the bare version", []string{"verseal", "-v"}, "dev"},
		{"unknown arg prints name and version", []string{"verseal", "status"}, "verseal dev"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			// Arrange
			var stdout, stderr bytes.Buffer

			// Act
			err := run(test.args, &stdout, &stderr)

			// Assert
			require.NoError(t, err)
			result := strings.TrimSpace(stdout.String())
			assert.Equal(t, test.expected, result)
			assert.Empty(t, stderr.String())
		})
	}
}
