package benchmark

import (
	"encoding/json"
	"fmt"
	"os"
	"sync"
	"time"
)

type Result struct {
	Timestamp    time.Time `json:"timestamp"`
	Category     string    `json:"category"`
	Model        string    `json:"model"`
	InputTokens  int       `json:"input_tokens"`
	OutputTokens int       `json:"output_tokens"`
	Latency      float64   `json:"latency_seconds"`
	Quality      float64   `json:"quality"`
	CostUSD      float64   `json:"cost_usd"`
}

type CategoryStats struct {
	Category     string             `json:"category"`
	ModelStats   map[string]*Stats  `json:"model_stats"`
	BestModel    string             `json:"best_model"`
}

type Stats struct {
	Count      int     `json:"count"`
	AvgQuality float64 `json:"avg_quality"`
	AvgLatency float64 `json:"avg_latency"`
	AvgCost    float64 `json:"avg_cost"`
	TotalCost  float64 `json:"total_cost"`
}

type Store struct {
	mu      sync.Mutex
	path    string
	results []Result
}

func NewStore(path string) (*Store, error) {
	s := &Store{path: path}
	if err := s.load(); err != nil && !os.IsNotExist(err) {
		return nil, fmt.Errorf("load benchmarks: %w", err)
	}
	return s, nil
}

func (s *Store) Record(r Result) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	r.Timestamp = time.Now()
	s.results = append(s.results, r)

	f, err := os.OpenFile(s.path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return fmt.Errorf("open results file: %w", err)
	}
	defer f.Close()

	return json.NewEncoder(f).Encode(r)
}

func (s *Store) StatsForCategory(category string) *CategoryStats {
	s.mu.Lock()
	defer s.mu.Unlock()

	cs := &CategoryStats{
		Category:   category,
		ModelStats:  make(map[string]*Stats),
	}

	for _, r := range s.results {
		if r.Category != category {
			continue
		}
		st, ok := cs.ModelStats[r.Model]
		if !ok {
			st = &Stats{}
			cs.ModelStats[r.Model] = st
		}
		st.Count++
		st.AvgQuality = (st.AvgQuality*float64(st.Count-1) + r.Quality) / float64(st.Count)
		st.AvgLatency = (st.AvgLatency*float64(st.Count-1) + r.Latency) / float64(st.Count)
		st.AvgCost = (st.AvgCost*float64(st.Count-1) + r.CostUSD) / float64(st.Count)
		st.TotalCost += r.CostUSD
	}

	bestScore := -1.0
	for model, st := range cs.ModelStats {
		if st.Count < 5 {
			continue
		}
		score := st.AvgQuality - (st.AvgCost * 100)
		if score > bestScore {
			bestScore = score
			cs.BestModel = model
		}
	}

	return cs
}

func (s *Store) RecommendModel(category string, qualityThreshold float64) string {
	cs := s.StatsForCategory(category)

	cheapest := ""
	cheapestCost := 999.0

	for model, st := range cs.ModelStats {
		if st.Count < 5 {
			continue
		}
		if st.AvgQuality >= qualityThreshold && st.AvgCost < cheapestCost {
			cheapestCost = st.AvgCost
			cheapest = model
		}
	}

	return cheapest
}

func (s *Store) AllStats() map[string]*CategoryStats {
	s.mu.Lock()
	categories := make(map[string]bool)
	for _, r := range s.results {
		categories[r.Category] = true
	}
	s.mu.Unlock()

	stats := make(map[string]*CategoryStats)
	for cat := range categories {
		stats[cat] = s.StatsForCategory(cat)
	}
	return stats
}

func (s *Store) load() error {
	f, err := os.Open(s.path)
	if err != nil {
		return err
	}
	defer f.Close()

	dec := json.NewDecoder(f)
	for dec.More() {
		var r Result
		if err := dec.Decode(&r); err != nil {
			continue
		}
		s.results = append(s.results, r)
	}
	return nil
}
