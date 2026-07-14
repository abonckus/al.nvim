// Package main implements a debug adapter protocol proxy for AL language server.
// This proxy intercepts DAP messages between the client and AL EditorServices,
// modifying responses to ensure proper command field handling.
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
)

// Constants for magic numbers and repeated strings
const (
	bufferSize          = 4096
	minArgsRequired     = 2
	contentLengthPrefix = "Content-Length: "
	headerSeparatorLF   = "\n\n"
	headerSeparatorCRLF = "\n\r\n"
	separatorLFLength   = 2
	separatorCRLFLength = 3
)

// DAPMessage represents a Debug Adapter Protocol message
type DAPMessage struct {
	RequestSeq *int        `json:"request_seq,omitempty"`
	Success    *bool       `json:"success,omitempty"`
	Type       string      `json:"type,omitempty"`
	Command    string      `json:"command,omitempty"`
	Body       interface{} `json:"body,omitempty"`
}

// Global channel to signal termination
var terminateSignal = make(chan bool, 1)

// Logging: the proxy owns stdin/stdout for the DAP protocol, so it must never
// log there. All diagnostics go to a file (and the child's stderr is teed into
// it too — that's where AL EditorServices' real errors surface).
var (
	logger  *log.Logger
	logFile *os.File
)

// initLogger opens the log file (path overridable via AL_DEBUG_PROXY_LOG,
// default <temp>/al-debug-proxy.log) and announces it on stderr so nvim-dap's
// adapter log points at it. Falls back to stderr if the file can't be opened.
func initLogger() {
	logPath := os.Getenv("AL_DEBUG_PROXY_LOG")
	if logPath == "" {
		logPath = filepath.Join(os.TempDir(), "al-debug-proxy.log")
	}
	// ponytail: single shared append file; fine for one debug session at a time.
	f, err := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		logger = log.New(os.Stderr, "", log.LstdFlags|log.Lmicroseconds)
		logf("failed to open log file %q: %v (logging to stderr)", logPath, err)
		return
	}
	logFile = f
	logger = log.New(f, "", log.LstdFlags|log.Lmicroseconds)
	fmt.Fprintf(os.Stderr, "al-debug-proxy logging to %s\n", logPath)
}

func logf(format string, args ...interface{}) {
	if logger != nil {
		logger.Printf(format, args...)
	}
}

// truncateForLog trims whitespace and caps a DAP payload so a single huge
// message can't blow up the log.
func truncateForLog(s string) string {
	const max = 4000
	s = strings.TrimSpace(s)
	if len(s) > max {
		return s[:max] + "...(truncated)"
	}
	return s
}

// fatalf logs the reason then exits. Every early-exit path uses this so a
// non-zero exit is never silent.
func fatalf(code int, format string, args ...interface{}) {
	logf(format, args...)
	os.Exit(code)
}

// childStderr tees the child process's stderr to both the proxy's stderr and
// the log file, so AL EditorServices exceptions are captured even if nvim-dap
// drops adapter stderr.
func childStderr() io.Writer {
	if logFile != nil {
		return io.MultiWriter(os.Stderr, logFile)
	}
	return os.Stderr
}

func main() {
	initLogger()
	logf("=== al-debug-proxy starting (pid %d) ===", os.Getpid())
	logf("args: %v", os.Args)

	// Check if we have arguments to pass to dotnet
	if len(os.Args) < minArgsRequired {
		fatalf(1, "not enough arguments: need at least %d, got %d", minArgsRequired, len(os.Args))
	}

	// Prepare the command: dotnet + all arguments passed to this proxy
	args := append([]string{"dotnet"}, os.Args[1:]...)
	logf("launching child: %v", args)
	// #nosec G204 - Command arguments are intentionally passed from command line
	cmd := exec.Command(args[0], args[1:]...)

	// Create pipes for communication
	stdinPipe, err := cmd.StdinPipe()
	if err != nil {
		fatalf(1, "failed to create stdin pipe: %v", err)
	}
	stdoutPipe, err := cmd.StdoutPipe()
	if err != nil {
		fatalf(1, "failed to create stdout pipe: %v", err)
	}
	cmd.Stderr = childStderr()

	// Configure process attributes (Windows-specific settings handled in separate function)
	configureProcess(cmd)

	// Start the AL EditorServices process
	if err := cmd.Start(); err != nil {
		fatalf(1, "failed to start child process %q (is dotnet on PATH?): %v", args[0], err)
	}
	logf("child started (pid %d)", cmd.Process.Pid)

	// Set up signal handling for graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)

	// Handle cleanup in a goroutine
	go func() {
		sig := <-sigChan
		logf("received signal %v, killing child", sig)
		if cmd.Process != nil {
			_ = cmd.Process.Kill() // Ignore error as process may have already exited
		}
		os.Exit(0)
	}()

	// Start goroutines to handle input/output
	go handleInput(stdinPipe)
	go handleOutput(stdoutPipe)

	// Wait for either the AL EditorServices process to complete or termination signal
	var waitErr error
	done := make(chan bool)
	go func() {
		waitErr = cmd.Wait()
		done <- true
	}()

	select {
	case <-done:
		// Process completed on its own
	case <-terminateSignal:
		// Received terminate command from the client: kill and exit cleanly.
		logf("terminate request received from client, killing child")
		if cmd.Process != nil {
			_ = cmd.Process.Kill() // Ignore error as process may have already exited
		}
		<-done // let cmd.Wait return
		logf("proxy exiting 0 (terminated by client)")
		os.Exit(0)
	}

	// Child exited on its own: mirror its exit code so a real failure is visible
	// to nvim-dap instead of being swallowed as a clean exit.
	code := 0
	if waitErr != nil {
		if exitErr, ok := waitErr.(*exec.ExitError); ok {
			code = exitErr.ExitCode()
		} else {
			code = 1
		}
		logf("child exited with error: %v (proxy exiting %d)", waitErr, code)
	} else {
		logf("child exited cleanly (proxy exiting 0)")
	}
	os.Exit(code)
}

// handleInput processes input from stdin and forwards to the process
func handleInput(writer io.WriteCloser) {
	defer writer.Close()

	// Read all data and process it as a stream, similar to handleOutput
	buffer := make([]byte, bufferSize)
	var accumulated []byte

	logf("handleInput: started")
	for {
		n, err := os.Stdin.Read(buffer)
		if n > 0 {
			logf("stdin: read %d bytes from client", n)
			accumulated = append(accumulated, buffer[:n]...)

			// Process complete messages from accumulated data
			for {
				processed, remaining := processInputBuffer(accumulated, writer)
				if processed == nil {
					break // No complete message found
				}

				accumulated = remaining
			}
		}

		if err != nil {
			if err == io.EOF {
				logf("stdin: EOF, input loop ending (client closed connection)")
				// Forward any remaining data
				if len(accumulated) > 0 {
					if _, writeErr := writer.Write(accumulated); writeErr != nil {
						// Error writing to pipe, connection may be closed
						break
					}
				}
				break
			}
			continue
		}
	}
}

// processInputBuffer looks for complete DAP messages in the input buffer and processes them
func processInputBuffer(data []byte, writer io.WriteCloser) (processed, remaining []byte) {
	dataStr := string(data)

	// Look for Content-Length header
	idx := strings.Index(dataStr, contentLengthPrefix)
	if idx == -1 {
		// No Content-Length found, return first part as-is if we have a complete line
		if newlineIdx := strings.Index(dataStr, "\n"); newlineIdx != -1 {
			if _, err := writer.Write(data[:newlineIdx+1]); err != nil {
				// Error writing to pipe, connection may be closed
				return data[:newlineIdx+1], data[newlineIdx+1:]
			}
			return data[:newlineIdx+1], data[newlineIdx+1:]
		}
		return nil, data // Wait for more data
	}

	// Parse content length
	headerEnd := strings.Index(dataStr[idx:], "\n")
	if headerEnd == -1 {
		return nil, data // Wait for complete header
	}
	headerEnd += idx

	lengthStr := strings.TrimSpace(dataStr[idx+len(contentLengthPrefix) : headerEnd])
	contentLength := 0
	if _, err := fmt.Sscanf(lengthStr, "%d", &contentLength); err != nil {
		// Can't parse length, forward up to this point
		_, _ = writer.Write(data[:headerEnd+1]) // Ignore write errors, connection may be closed
		return data[:headerEnd+1], data[headerEnd+1:]
	}

	// Find the start of JSON content (after the empty line)
	jsonStart := strings.Index(dataStr[headerEnd:], headerSeparatorLF)
	if jsonStart == -1 {
		jsonStart = strings.Index(dataStr[headerEnd:], headerSeparatorCRLF)
		if jsonStart == -1 {
			return nil, data // Wait for complete separator
		}
		jsonStart += headerEnd + separatorCRLFLength
	} else {
		jsonStart += headerEnd + separatorLFLength
	}

	// Check if we have the complete JSON content
	if len(data) < jsonStart+contentLength {
		return nil, data // Wait for complete message
	}

	// Extract and check the JSON content for terminate command
	jsonContent := string(data[jsonStart : jsonStart+contentLength])
	logf("client --> child: %s", truncateForLog(jsonContent))
	checkForTerminate(jsonContent)

	// Forward the complete message unchanged
	messageEnd := jsonStart + contentLength
	if _, err := writer.Write(data[:messageEnd]); err != nil {
		// Error writing to pipe, connection may be closed
	}

	return data[:messageEnd], data[messageEnd:]
}

// checkForTerminate checks if the message is a terminate request
func checkForTerminate(jsonContent string) {
	var msg DAPMessage

	// Try to parse the JSON
	if err := json.Unmarshal([]byte(jsonContent), &msg); err != nil {
		return // If parsing fails, ignore
	}

	// Check if this is a terminate request
	if msg.Type == "request" && msg.Command == "terminate" {
		// Signal termination
		select {
		case terminateSignal <- true:
		default:
			// Channel already has a signal, don't block
		}
	}
}

// handleOutput processes output from the process and forwards to stdout
func handleOutput(reader io.ReadCloser) {
	defer reader.Close()

	logf("handleOutput: started")

	// Simple approach: read all data and process it as a stream
	buffer := make([]byte, bufferSize)
	var accumulated []byte

	for {
		n, err := reader.Read(buffer)
		if n > 0 {
			accumulated = append(accumulated, buffer[:n]...)

			// Process complete messages from accumulated data
			for {
				processed, remaining := processBuffer(accumulated)
				if processed == nil {
					break // No complete message found
				}

				// Output the processed message
				// #nosec G104 - stdout write errors are not critical for proxy operation
				os.Stdout.Write(processed)
				accumulated = remaining
			}
		}

		if err != nil {
			if err == io.EOF {
				logf("child stdout: EOF, output loop ending (child closed its output)")
				// Output any remaining data
				if len(accumulated) > 0 {
					// #nosec G104 - stdout write errors are not critical for proxy operation
					os.Stdout.Write(accumulated)
				}
				break
			}
			continue
		}
	}
}

// processBuffer looks for complete DAP messages in the buffer and processes them
func processBuffer(data []byte) (processed, remaining []byte) {
	dataStr := string(data)

	// Look for Content-Length header
	idx := strings.Index(dataStr, contentLengthPrefix)
	if idx == -1 {
		// No Content-Length found, return first part as-is if we have a complete line
		if newlineIdx := strings.Index(dataStr, "\n"); newlineIdx != -1 {
			return data[:newlineIdx+1], data[newlineIdx+1:]
		}
		return nil, data // Wait for more data
	}

	// Parse content length
	headerStart := idx
	headerEnd := strings.Index(dataStr[idx:], "\n")
	if headerEnd == -1 {
		return nil, data // Wait for complete header
	}
	headerEnd += idx

	lengthStr := strings.TrimSpace(dataStr[idx+len(contentLengthPrefix) : headerEnd])
	contentLength := 0
	if _, err := fmt.Sscanf(lengthStr, "%d", &contentLength); err != nil {
		// Can't parse length, return up to this point
		return data[:headerEnd+1], data[headerEnd+1:]
	}

	// Find the start of JSON content (after the empty line)
	jsonStart := strings.Index(dataStr[headerEnd:], headerSeparatorLF)
	if jsonStart == -1 {
		jsonStart = strings.Index(dataStr[headerEnd:], headerSeparatorCRLF)
		if jsonStart == -1 {
			return nil, data // Wait for complete separator
		}
		jsonStart += headerEnd + separatorCRLFLength
	} else {
		jsonStart += headerEnd + separatorLFLength
	}

	// Check if we have the complete JSON content
	if len(data) < jsonStart+contentLength {
		return nil, data // Wait for complete message
	}

	// Extract and process the JSON content
	jsonContent := string(data[jsonStart : jsonStart+contentLength])
	logf("child --> client: %s", truncateForLog(jsonContent))
	modifiedContent := processMessage(jsonContent)

	// Build the complete message
	var result []byte
	if modifiedContent != jsonContent {
		// Content was modified, update the Content-Length
		newLength := len(modifiedContent)
		result = append(result, data[:headerStart]...)
		result = append(result, fmt.Sprintf("Content-Length: %d\r\n\r\n%s", newLength, modifiedContent)...)
	} else {
		// Content unchanged, return original
		result = append(result, data[:jsonStart+contentLength]...)
	}

	return result, data[jsonStart+contentLength:]
}

// processMessage checks if the message matches our target response and modifies it
func processMessage(jsonContent string) string {
	var msg DAPMessage

	// Try to parse the JSON
	if err := json.Unmarshal([]byte(jsonContent), &msg); err != nil {
		// If parsing fails, return original content
		return jsonContent
	}

	// Check if this matches our target response pattern:
	// - Must be a response type
	// - Must be successful
	// - Must have a request_seq
	// - Must NOT already have a command set (empty string or missing)
	if msg.Type == "response" && msg.Success != nil && *msg.Success && msg.RequestSeq != nil && msg.Command == "" {
		// Add the command field only if it's not already set
		msg.Command = "empty"

		// Marshal back to JSON
		if modifiedJSON, err := json.Marshal(msg); err == nil {
			return string(modifiedJSON)
		}
	}

	// Return original content if:
	// - No modification needed (doesn't match pattern)
	// - Already has a command set (forward as-is)
	// - Marshaling failed
	return jsonContent
}
