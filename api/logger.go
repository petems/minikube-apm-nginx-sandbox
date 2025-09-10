package main

import (
	"io"
	"os"

	"github.com/sirupsen/logrus"
	ddtracelogrus "gopkg.in/DataDog/dd-trace-go.v1/contrib/sirupsen/logrus"
)

type Logger struct {
	*logrus.Logger
}

func NewLogger(fpath string) *Logger {
	log := logrus.New()

	file, err := os.OpenFile(fpath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0666)
	if err == nil {
		mw := io.MultiWriter(os.Stdout, file)
		log.SetOutput(mw)
	} else {
		log.Info("Failed to log to file, using default stderr")
	}

	log.SetFormatter(&logrus.JSONFormatter{})
	log.SetLevel(logrus.InfoLevel)
	log.AddHook(&ddtracelogrus.DDContextLogHook{})
	return &Logger{log}
}
