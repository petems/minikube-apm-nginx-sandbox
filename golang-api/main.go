package main

import (
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"time"

	"github.com/sirupsen/logrus"
	muxtrace "gopkg.in/DataDog/dd-trace-go.v1/contrib/gorilla/mux"
	"gopkg.in/DataDog/dd-trace-go.v1/ddtrace/ext"
	"gopkg.in/DataDog/dd-trace-go.v1/ddtrace/tracer"
)

var log = NewLogger("/app/logs/prod.log")

// ErrorResponse represents a structured error response
type ErrorResponse struct {
	Error     string `json:"error"`
	Message   string `json:"message"`
	Code      string `json:"code"`
	Timestamp string `json:"timestamp"`
	RequestID string `json:"request_id,omitempty"`
}

// SuccessResponse represents a successful response
type SuccessResponse struct {
	Status    string `json:"status"`
	Message   string `json:"message"`
	Timestamp string `json:"timestamp"`
	RequestID string `json:"request_id,omitempty"`
}

// Error scenarios for realistic simulation
type ErrorScenario struct {
	StatusCode int
	ErrorCode  string
	Message    string
	Reason     string
}

var errorScenarios = []ErrorScenario{
	{http.StatusBadRequest, "INVALID_REQUEST", "Invalid request format", "Missing required parameter 'user_id'"},
	{http.StatusBadRequest, "VALIDATION_ERROR", "Request validation failed", "Email format is invalid"},
	{http.StatusBadRequest, "MISSING_AUTH", "Authentication required", "Authorization header is missing or malformed"},
	{http.StatusInternalServerError, "DATABASE_ERROR", "Internal database error", "Connection to user database failed"},
	{http.StatusInternalServerError, "SERVICE_UNAVAILABLE", "External service error", "Payment service is temporarily unavailable"},
	{http.StatusInternalServerError, "TIMEOUT_ERROR", "Request timeout", "Upstream service did not respond within 30 seconds"},
}

func randomStatusHandler(w http.ResponseWriter, r *http.Request) {
	rctx := r.Context()
	span, sctx := tracer.StartSpanFromContext(rctx, "http.request")
	defer span.Finish()

	// Generate unique request ID for tracing
	requestID := fmt.Sprintf("req_%d", time.Now().UnixNano())
	span.SetTag("request.id", requestID)
	span.SetTag("http.method", r.Method)
	span.SetTag("http.url", r.URL.String())

	// Extract trace and span IDs for enhanced logging visibility
	spanContext := span.Context()
	traceID := spanContext.TraceID()
	spanID := spanContext.SpanID()

	loge := log.
		WithContext(sctx).
		WithFields(logrus.Fields{
			"url":        r.URL.String(),
			"method":     r.Method,
			"remote_addr": r.RemoteAddr,
			"request_id": requestID,
			"user_agent": r.UserAgent(),
			// Add both decimal and hex formats for easier correlation with nginx logs
			"trace_id_dec": traceID,
			"trace_id_hex": fmt.Sprintf("%016x", traceID),
			"span_id_dec":  spanID,
			"span_id_hex":  fmt.Sprintf("%016x", spanID),
		})

	// Set content type for JSON responses
	w.Header().Set("Content-Type", "application/json")

	// Simulate different outcomes: 50% success, 30% client error, 20% server error
	rand.Seed(time.Now().UnixNano())
	outcome := rand.Float64()
	
	timestamp := time.Now().UTC().Format(time.RFC3339)

	if outcome < 0.5 {
		// Success case
		span.SetTag("http.status_code", http.StatusOK)
		span.SetTag(ext.HTTPCode, "200")
		
		response := SuccessResponse{
			Status:    "success",
			Message:   "Request processed successfully",
			Timestamp: timestamp,
			RequestID: requestID,
		}
		
		loge.WithFields(logrus.Fields{
			"status_code": http.StatusOK,
			"response":    "success",
		}).Info("Request processed successfully")
		
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(response)
		
	} else if outcome < 0.8 {
		// Client error (400)
		scenario := errorScenarios[rand.Intn(3)] // First 3 are 400 errors
		
		span.SetTag("http.status_code", scenario.StatusCode)
		span.SetTag(ext.HTTPCode, fmt.Sprintf("%d", scenario.StatusCode))
		span.SetTag(ext.Error, true)
		span.SetTag("error.type", "client_error")
		span.SetTag("error.code", scenario.ErrorCode)
		span.SetTag("error.message", scenario.Message)
		
		response := ErrorResponse{
			Error:     scenario.ErrorCode,
			Message:   scenario.Message,
			Code:      scenario.Reason,
			Timestamp: timestamp,
			RequestID: requestID,
		}
		
		loge.WithFields(logrus.Fields{
			"status_code":  scenario.StatusCode,
			"error_code":   scenario.ErrorCode,
			"error_message": scenario.Message,
			"error_reason": scenario.Reason,
			"error_type":   "client_error",
		}).Error("Client error occurred")
		
		w.WriteHeader(scenario.StatusCode)
		json.NewEncoder(w).Encode(response)
		
	} else {
		// Server error (500)
		scenario := errorScenarios[3+rand.Intn(3)] // Last 3 are 500 errors
		
		span.SetTag("http.status_code", scenario.StatusCode)
		span.SetTag(ext.HTTPCode, fmt.Sprintf("%d", scenario.StatusCode))
		span.SetTag(ext.Error, true)
		span.SetTag("error.type", "server_error")
		span.SetTag("error.code", scenario.ErrorCode)
		span.SetTag("error.message", scenario.Message)
		
		response := ErrorResponse{
			Error:     scenario.ErrorCode,
			Message:   scenario.Message,
			Code:      scenario.Reason,
			Timestamp: timestamp,
			RequestID: requestID,
		}
		
		loge.WithFields(logrus.Fields{
			"status_code":  scenario.StatusCode,
			"error_code":   scenario.ErrorCode,
			"error_message": scenario.Message,
			"error_reason": scenario.Reason,
			"error_type":   "server_error",
		}).Error("Server error occurred")
		
		w.WriteHeader(scenario.StatusCode)
		json.NewEncoder(w).Encode(response)
	}
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	
	response := SuccessResponse{
		Status:    "healthy",
		Message:   "Service is healthy",
		Timestamp: time.Now().UTC().Format(time.RFC3339),
	}
	
	json.NewEncoder(w).Encode(response)
}

func main() {
	tracer.Start()
	defer tracer.Stop()

	r := muxtrace.NewRouter()
	r.HandleFunc("/", randomStatusHandler)
	r.HandleFunc("/health", healthHandler)

	log.Println("Started")
	log.Fatal(http.ListenAndServe(":8080", r))
}
