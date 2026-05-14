package ollama

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

type Client struct {
	host   string
	client *http.Client
}

type GenerateRequest struct {
	Model  string `json:"model"`
	Prompt string `json:"prompt"`
	System string `json:"system,omitempty"`
	Stream bool   `json:"stream"`
}

type GenerateResponse struct {
	Response           string `json:"response"`
	TotalDuration      int64  `json:"total_duration"`
	PromptEvalCount    int    `json:"prompt_eval_count"`
	EvalCount          int    `json:"eval_count"`
}

type Result struct {
	Output       string
	Model        string
	InputTokens  int
	OutputTokens int
	Latency      time.Duration
}

func NewClient(host string) *Client {
	return &Client{
		host:   host,
		client: &http.Client{Timeout: 5 * time.Minute},
	}
}

func (c *Client) Generate(ctx context.Context, model, system, prompt string) (*Result, error) {
	start := time.Now()

	body, err := json.Marshal(GenerateRequest{
		Model:  model,
		Prompt: prompt,
		System: system,
		Stream: false,
	})
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.host+"/api/generate", bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("send request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("ollama error %d: %s", resp.StatusCode, string(b))
	}

	var genResp GenerateResponse
	if err := json.NewDecoder(resp.Body).Decode(&genResp); err != nil {
		return nil, fmt.Errorf("decode response: %w", err)
	}

	return &Result{
		Output:       genResp.Response,
		Model:        model,
		InputTokens:  genResp.PromptEvalCount,
		OutputTokens: genResp.EvalCount,
		Latency:      time.Since(start),
	}, nil
}

func (c *Client) Healthy(ctx context.Context) bool {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.host+"/api/tags", nil)
	if err != nil {
		return false
	}
	resp, err := c.client.Do(req)
	if err != nil {
		return false
	}
	resp.Body.Close()
	return resp.StatusCode == http.StatusOK
}
