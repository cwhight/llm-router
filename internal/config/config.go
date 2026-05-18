package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Claude     ClaudeConfig     `yaml:"claude"`
	Ollama     OllamaConfig     `yaml:"ollama"`
	Routing    RoutingConfig    `yaml:"routing"`
	Benchmarks BenchmarkConfig  `yaml:"benchmarks"`
	Metrics    MetricsConfig    `yaml:"metrics"`
}

type ClaudeConfig struct {
	APIKey       string `yaml:"api_key"`
	DefaultModel string `yaml:"default_model"`
	OpusModel    string `yaml:"opus_model"`
	HaikuModel   string `yaml:"haiku_model"`
}

type OllamaConfig struct {
	Host   string            `yaml:"host"`
	APIKey string            `yaml:"api_key"`
	Models map[string]string `yaml:"models"`
}

type RoutingConfig struct {
	QualityThreshold float64           `yaml:"quality_threshold"`
	Defaults         map[string]string `yaml:"defaults"`
	ClaudeOnly       []string          `yaml:"claude_only"`
}

type BenchmarkConfig struct {
	SampleRate      float64 `yaml:"sample_rate"`
	ResultsFile     string  `yaml:"results_file"`
	ReevalThreshold int     `yaml:"reeval_threshold"`
}

type MetricsConfig struct {
	Enabled bool   `yaml:"enabled"`
	Addr    string `yaml:"addr"`
}

func DefaultConfigPath() string {
	if v := os.Getenv("LLM_ROUTER_CONFIG"); v != "" {
		return v
	}
	home, _ := os.UserHomeDir()
	return home + "/.config/llm-router/config.yaml"
}

func DefaultBenchmarksPath() string {
	home, _ := os.UserHomeDir()
	return home + "/.config/llm-router/benchmarks/results.jsonl"
}

func DefaultRoutingLogPath() string {
	home, _ := os.UserHomeDir()
	return home + "/.config/llm-router/routing.log"
}

func Load(path string) (*Config, error) {
	if path == "" {
		path = DefaultConfigPath()
	}

	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read config: %w", err)
	}

	expanded := os.ExpandEnv(string(data))

	var cfg Config
	if err := yaml.Unmarshal([]byte(expanded), &cfg); err != nil {
		return nil, fmt.Errorf("parse config: %w", err)
	}

	if cfg.Claude.APIKey == "" {
		cfg.Claude.APIKey = os.Getenv("ANTHROPIC_API_KEY")
	}

	return &cfg, nil
}

// FindProjectConfig walks up from the current working directory looking for
// .llm-router.yaml, stopping at the home directory or filesystem root.
func FindProjectConfig() string {
	home, _ := os.UserHomeDir()
	dir, err := os.Getwd()
	if err != nil {
		return ""
	}
	for {
		candidate := filepath.Join(dir, ".llm-router.yaml")
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
		if dir == home || dir == "/" {
			break
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return ""
}

// LoadWithProjectOverride loads the global config then merges any .llm-router.yaml
// found by walking up from the current working directory.
func LoadWithProjectOverride(globalPath string) (*Config, error) {
	cfg, err := Load(globalPath)
	if err != nil {
		return nil, err
	}
	projectPath := FindProjectConfig()
	if projectPath == "" {
		return cfg, nil
	}
	data, err := os.ReadFile(projectPath)
	if err != nil {
		return cfg, nil // project config unreadable — fall back to global
	}
	var override Config
	if err := yaml.Unmarshal([]byte(os.ExpandEnv(string(data))), &override); err != nil {
		return cfg, nil // malformed project config — fall back to global
	}
	mergeConfig(cfg, &override)
	return cfg, nil
}

func mergeConfig(base, override *Config) {
	if override.Ollama.Host != "" {
		base.Ollama.Host = override.Ollama.Host
	}
	for k, v := range override.Ollama.Models {
		if base.Ollama.Models == nil {
			base.Ollama.Models = map[string]string{}
		}
		base.Ollama.Models[k] = v
	}
	if override.Routing.QualityThreshold != 0 {
		base.Routing.QualityThreshold = override.Routing.QualityThreshold
	}
	for k, v := range override.Routing.Defaults {
		if base.Routing.Defaults == nil {
			base.Routing.Defaults = map[string]string{}
		}
		base.Routing.Defaults[k] = v
	}
	if len(override.Routing.ClaudeOnly) > 0 {
		base.Routing.ClaudeOnly = override.Routing.ClaudeOnly
	}
	if override.Claude.APIKey != "" {
		base.Claude.APIKey = override.Claude.APIKey
	}
	if override.Claude.DefaultModel != "" {
		base.Claude.DefaultModel = override.Claude.DefaultModel
	}
	if override.Claude.OpusModel != "" {
		base.Claude.OpusModel = override.Claude.OpusModel
	}
	if override.Claude.HaikuModel != "" {
		base.Claude.HaikuModel = override.Claude.HaikuModel
	}
}

func (c *Config) IsClaudeOnly(category string) bool {
	for _, co := range c.Routing.ClaudeOnly {
		if strings.EqualFold(co, category) {
			return true
		}
	}
	return false
}
