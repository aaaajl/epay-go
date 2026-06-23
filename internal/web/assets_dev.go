//go:build !embed

package web

import "embed"

var buildFS embed.FS

var indexPage []byte
