.PHONY: build-frontend build run dev-backend dev-frontend package-docker

build-frontend:
	./scripts/build-frontend.sh

build: build-frontend
	CGO_ENABLED=0 go build -tags embed -o epay-server ./cmd/server

run: build
	./epay-server

dev-backend:
	go run ./cmd/server

dev-frontend:
	cd web && npm run dev

package-docker:
	./scripts/package-docker.sh
