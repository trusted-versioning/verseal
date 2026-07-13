//go:build unit

package version

import (
	"testing"

	"github.com/Masterminds/semver/v3"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func mustVersion(t *testing.T, raw string) *semver.Version {
	t.Helper()
	parsed, err := semver.NewVersion(raw)
	require.NoError(t, err)
	return parsed
}

func Test_unit_ApplyBump(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		bump     Bump
		expected string
	}{
		{"none leaves the version unchanged", "1.2.3", None, "1.2.3"},
		{"patch increments the patch", "1.2.3", Patch, "1.2.4"},
		{"minor increments the minor and resets patch", "1.2.3", Minor, "1.3.0"},
		{"major increments the major and resets minor and patch", "1.2.3", Major, "2.0.0"},
		{"minor on a zero version", "0.0.0", Minor, "0.1.0"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			// Arrange
			base := mustVersion(t, test.input)

			// Act
			result := ApplyBump(base, test.bump)

			// Assert
			assert.Equal(t, test.expected, result.String())
		})
	}
}

func Test_unit_Max(t *testing.T) {
	tests := []struct {
		name     string
		first    Bump
		second   Bump
		expected Bump
	}{
		{"higher second wins", Patch, Major, Major},
		{"higher first wins", Minor, Patch, Minor},
		{"equal bumps", None, None, None},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			// Act
			result := Max(test.first, test.second)

			// Assert
			assert.Equal(t, test.expected, result)
		})
	}
}

func Test_unit_String(t *testing.T) {
	tests := []struct {
		bump     Bump
		expected string
	}{
		{None, "none"},
		{Patch, "patch"},
		{Minor, "minor"},
		{Major, "major"},
	}
	for _, test := range tests {
		t.Run(test.expected, func(t *testing.T) {
			// Act
			result := test.bump.String()

			// Assert
			assert.Equal(t, test.expected, result)
		})
	}
}
