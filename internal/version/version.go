// Package version owns the bump vocabulary and semver application.
package version

import "github.com/Masterminds/semver/v3"

type Bump int

const (
	None  Bump = iota
	Patch Bump = iota
	Minor Bump = iota
	Major Bump = iota
)

func (bump Bump) String() string {
	switch bump {
	case Major:
		return "major"
	case Minor:
		return "minor"
	case Patch:
		return "patch"
	default:
		return "none"
	}
}

func Max(first, second Bump) Bump {
	if first > second {
		return first
	}
	return second
}

func ApplyBump(base *semver.Version, bump Bump) *semver.Version {
	switch bump {
	case Major:
		next := base.IncMajor()
		return &next
	case Minor:
		next := base.IncMinor()
		return &next
	case Patch:
		next := base.IncPatch()
		return &next
	default:
		return base
	}
}
