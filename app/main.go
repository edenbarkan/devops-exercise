// Command hello serves a small HTML page showing a message, the build version
// and the pod that served the request. It shuts down gracefully on SIGTERM so
// Kubernetes rolling updates drop no requests.
package main

import (
	"context"
	"errors"
	"html/template"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"sync/atomic"
	"syscall"
	"time"
)

// message is a code constant on purpose: changing it must go through the full
// CI -> image -> GitOps pipeline.
const message = "Hello from GitOps!"

// version is injected at build time: -ldflags "-X main.version=<git sha>".
var version = "dev"

var page = template.Must(template.New("page").Parse(`<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>hello</title></head>
<body>
<main>
<h1>{{.Message}}</h1>
<p>Version: <code>{{.Version}}</code></p>
<p>Pod: <code>{{.Pod}}</code></p>
</main>
</body>
</html>
`))

type pageData struct {
	Message, Version, Pod string
}

// newMux builds the HTTP routes. ready is flipped to false on SIGTERM so the
// readiness probe fails and the pod is taken out of Service endpoints.
func newMux(ready *atomic.Bool, pod string) *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		if err := page.Execute(w, pageData{message, version, pod}); err != nil {
			slog.Error("render", "err", err)
		}
	})
	// Liveness: the process is up.
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	// Readiness: willing to take new traffic.
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, _ *http.Request) {
		if !ready.Load() {
			http.Error(w, "shutting down", http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
	})
	return mux
}

func main() {
	pod := os.Getenv("POD_NAME")
	if pod == "" {
		pod, _ = os.Hostname()
	}
	addr := ":" + envOr("PORT", "8080")

	var ready atomic.Bool
	ready.Store(true)

	srv := &http.Server{
		Addr:              addr,
		Handler:           newMux(&ready, pod),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)
	defer stop()

	go func() {
		slog.Info("listening", "addr", addr, "version", version, "pod", pod)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("listen", "err", err)
			os.Exit(1)
		}
	}()

	<-ctx.Done()
	ready.Store(false)
	slog.Info("SIGTERM received, draining")

	// Kubernetes waits terminationGracePeriodSeconds (30s); preStop already
	// slept 5s, so finish within the remaining budget.
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		slog.Error("shutdown", "err", err)
		os.Exit(1)
	}
	slog.Info("stopped cleanly")
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
