NGINX_PORT := 8080

.PHONY: stress stress-golang stress-nodejs stress-both
stress: stress-both

stress-golang:
	echo "GET http://127.0.0.1:${NGINX_PORT}/golang-api/" | \
		vegeta attack -rate=100 -duration=30s | \
		vegeta report

stress-nodejs:
	echo "GET http://127.0.0.1:${NGINX_PORT}/nodejs-api/" | \
		vegeta attack -rate=100 -duration=30s | \
		vegeta report

stress-both:
	@echo "Stress testing both APIs..."
	@echo "Golang API stress test:"
	@echo "GET http://127.0.0.1:${NGINX_PORT}/golang-api/" | \
		vegeta attack -rate=50 -duration=30s | \
		vegeta report
	@echo ""
	@echo "Node.js API stress test:"
	@echo "GET http://127.0.0.1:${NGINX_PORT}/nodejs-api/" | \
		vegeta attack -rate=50 -duration=30s | \
		vegeta report

.PHONY: test-health
test-health:
	@echo "Testing health endpoints..."
	@curl -s http://127.0.0.1:${NGINX_PORT}/golang-api/health | jq .
	@curl -s http://127.0.0.1:${NGINX_PORT}/nodejs-api/health | jq .

.PHONY: test-apis
test-apis:
	@echo "Testing both APIs..."
	@echo "Golang API response:"
	@curl -s http://127.0.0.1:${NGINX_PORT}/golang-api/ | jq .
	@echo ""
	@echo "Node.js API response:"
	@curl -s http://127.0.0.1:${NGINX_PORT}/nodejs-api/ | jq .
