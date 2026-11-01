// Command gocost prices Go's goroutines as context for ThreadCost.m9
// (docs/task-plan.md, stage 0).  It is context, not a target.
//
//	gocost create N     N goroutines one after another; each signals
//	                    that it ran before the next starts.
//	gocost burst N      N goroutines started at once, then awaited.
//	gocost pingpong N   N round trips over two unbuffered channels.
//	gocost idle N       N goroutines parked on a channel, then released.
//
// The modes match ThreadCost's.  The clock is time.Now around the
// measured part only.
package main

import (
	"fmt"
	"os"
	"strconv"
	"sync"
	"time"
)

func report(mode string, n int, d time.Duration, unit string) {
	s := d.Seconds()
	fmt.Printf("%s n=%d total_s=%g per_us=%g %s\n", mode, n, s, s*1e6/float64(n), unit)
}

func main() {
	if len(os.Args) < 3 {
		fmt.Fprintln(os.Stderr, "usage: gocost create|burst|pingpong|idle N")
		os.Exit(2)
	}
	mode := os.Args[1]
	n, err := strconv.Atoi(os.Args[2])
	if err != nil {
		fmt.Fprintln(os.Stderr, "gocost: bad N")
		os.Exit(2)
	}
	switch mode {
	case "create":
		done := make(chan struct{})
		t0 := time.Now()
		for i := 0; i < n; i++ {
			go func() { done <- struct{}{} }()
			<-done
		}
		report("create", n, time.Since(t0), "per goroutine, start to its signal seen")
	case "burst":
		var wg sync.WaitGroup
		t0 := time.Now()
		wg.Add(n)
		for i := 0; i < n; i++ {
			go func() { wg.Done() }()
		}
		t1 := time.Now()
		wg.Wait()
		report("burst-start", n, t1.Sub(t0), "per go statement")
		report("burst-all", n, time.Since(t0), "per goroutine, all done")
	case "pingpong":
		ping := make(chan int)
		pong := make(chan int)
		go func() {
			for v := range ping {
				pong <- v
			}
		}()
		t0 := time.Now()
		for i := 0; i < n; i++ {
			ping <- i
			<-pong
		}
		report("pingpong", n, time.Since(t0), "per round trip")
		close(ping)
	case "idle":
		var arrived, finished sync.WaitGroup
		gate := make(chan struct{})
		arrived.Add(n)
		finished.Add(n)
		t0 := time.Now()
		for i := 0; i < n; i++ {
			go func() {
				arrived.Done()
				<-gate
				finished.Done()
			}()
		}
		arrived.Wait()
		t1 := time.Now()
		time.Sleep(2 * time.Second)
		t2 := time.Now()
		close(gate)
		finished.Wait()
		report("idle-park", n, t1.Sub(t0), "per goroutine, start to parked")
		report("idle-release", n, time.Since(t2), "per goroutine, one close to all done")
	default:
		fmt.Fprintln(os.Stderr, "unknown mode", mode)
		os.Exit(2)
	}
}
