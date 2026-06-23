package web

import (
	"embed"
	"io/fs"
	"net/http"
	"os"
	"strings"

	"github.com/gin-contrib/gzip"
	"github.com/gin-contrib/static"
	"github.com/gin-gonic/gin"
)

type embedFileSystem struct {
	http.FileSystem
}

func (e *embedFileSystem) Exists(_ string, path string) bool {
	_, err := e.Open(path)
	return err == nil
}

func (e *embedFileSystem) Open(name string) (http.File, error) {
	if name == "/" {
		// 根路径交给 NoRoute，统一返回 index.html（SPA 路由）
		return nil, os.ErrNotExist
	}
	return e.FileSystem.Open(name)
}

func embedFolder(fsEmbed embed.FS, targetPath string) static.ServeFileSystem {
	sub, err := fs.Sub(fsEmbed, targetPath)
	if err != nil {
		panic(err)
	}
	return &embedFileSystem{FileSystem: http.FS(sub)}
}

// SetupStatic 注册嵌入式前端静态资源与 SPA 回退路由（仅 embed 构建生效）
func SetupStatic(r *gin.Engine) {
	if len(indexPage) == 0 {
		return
	}

	staticFS := embedFolder(buildFS, "dist")

	r.Use(gzip.Gzip(gzip.DefaultCompression))
	r.Use(static.Serve("/", staticFS))
	r.NoRoute(func(c *gin.Context) {
		path := c.Request.URL.Path
		if isBackendPath(path) {
			c.JSON(http.StatusNotFound, gin.H{"code": 404, "msg": "not found"})
			return
		}

		c.Header("Cache-Control", "no-cache")
		c.Data(http.StatusOK, "text/html; charset=utf-8", indexPage)
	})
}

func isBackendPath(path string) bool {
	return strings.HasPrefix(path, "/api") ||
		strings.HasPrefix(path, "/assets") ||
		path == "/health" ||
		path == "/submit.php" ||
		path == "/mapi.php" ||
		path == "/api.php"
}
