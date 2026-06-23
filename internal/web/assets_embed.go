//go:build embed

package web

import "embed"

//go:embed dist
var buildFS embed.FS

//go:embed dist/index.html
var indexPage []byte
