package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
)

func TestRoutes(t *testing.T) {
	var ready atomic.Bool
	ready.Store(true)
	srv := httptest.NewServer(newMux(&ready, "pod-<x>"))
	defer srv.Close()

	get := func(path string) (*http.Response, string) {
		t.Helper()
		resp, err := http.Get(srv.URL + path)
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		b, err := io.ReadAll(resp.Body)
		if err != nil {
			t.Fatal(err)
		}
		return resp, string(b)
	}

	resp, body := get("/")
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("/ status = %d", resp.StatusCode)
	}
	for _, want := range []string{message, version, "pod-&lt;x&gt;"} {
		if !strings.Contains(body, want) {
			t.Errorf("/ body missing %q (template must escape)", want)
		}
	}

	if r, _ := get("/healthz"); r.StatusCode != http.StatusOK {
		t.Errorf("/healthz = %d", r.StatusCode)
	}
	if r, _ := get("/readyz"); r.StatusCode != http.StatusOK {
		t.Errorf("/readyz ready = %d", r.StatusCode)
	}

	ready.Store(false)
	if r, _ := get("/readyz"); r.StatusCode != http.StatusServiceUnavailable {
		t.Errorf("/readyz draining = %d, want 503", r.StatusCode)
	}
	if r, _ := get("/nope"); r.StatusCode != http.StatusNotFound {
		t.Errorf("/nope = %d, want 404", r.StatusCode)
	}
}
