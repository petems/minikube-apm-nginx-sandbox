NGINX_PORT := 8888

.PHONY: stress
stress:
	echo "GET http://127.0.0.1:${NGINX_PORT}" | \
		vegeta attack -rate=1000 -duration=60s | \
		vegeta report
