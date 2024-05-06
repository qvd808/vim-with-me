package ansiparser

import (
	//"github.com/leaanthony/go-ansi-parser"
	"bytes"

	"github.com/leaanthony/go-ansi-parser"
	"github.com/theprimeagen/vim-with-me/pkg/assert"
)

type Frame struct {
	Color []byte
	Chars []byte
}

type Ansi8BitFramer struct {
	rows int
	cols int

	ch          chan Frame
	currentIdx  int
	currentCol  int
	currentRow  int
	buffer      []byte
	colorOffset int
	scratch     []byte
}

func nextAnsiChunk(data []byte, idx int) (bool, int, *ansi.StyledText, error) {
	data = data[idx:]
    assert.Assert(data[0] == '', "the ansi chunks should always start on an escape")

	nextEsc := bytes.Index(data[1:], []byte{''}) + 1

	var styles []*ansi.StyledText = nil
	var err error = nil
	out := 0
	var complete = nextEsc != 0
	if complete {
		out = nextEsc
		styles, err = ansi.Parse(string(data[:nextEsc]))
	} else {
		styles, err = ansi.Parse(string(data))
		out = len(data)
	}

	if styles != nil && len(styles) != 0 {
		assert.Assert(len(styles) == 1, "there must only be one style at a time parsed")
		return complete, out, styles[0], err
	}
	return complete, out, nil, err
}

// TODO: I could also use a ctx to close out everything
func New8BitFramer() *Ansi8BitFramer {

	// 1 byte color, 1 byte ascii
	return &Ansi8BitFramer{
		ch:         make(chan Frame, 10),
		currentIdx: 0,
		currentCol: 0,
		currentRow: 0, // makes life easier
		buffer:     make([]byte, 0, 0),
		scratch:    make([]byte, 0),
	}
}

func (a *Ansi8BitFramer) WithDim(rows, cols int) *Ansi8BitFramer {
	length := rows * cols
	a.rows = rows
	a.cols = cols
	a.colorOffset = length
	a.buffer = make([]byte, length*2, length*2)

	return a
}

func RGBTo8BitColor(hex ansi.Rgb) uint {
	red := uint(hex.R) * 8 / 256
	green := uint(hex.G) * 8 / 256
	blue := uint(hex.B) * 4 / 256

	return (red << 5) | (green << 2) | blue
}

func remainingIsRegisteredNurse(data []byte) bool {
	if len(data) != 3 {
		return false
	}

	return data[1] == '\r' && data[2] == '\n'
}

func (framer *Ansi8BitFramer) place(color, char byte) {
	framer.buffer[framer.currentIdx] = char
	framer.buffer[framer.colorOffset+framer.currentIdx] = color
	framer.currentIdx++
	framer.currentCol++
}

func (framer *Ansi8BitFramer) fillRemainingRow() {
	for framer.currentCol < framer.cols {
		framer.place(0, ' ')
	}
}

func (framer *Ansi8BitFramer) Write(data []byte) (int, error) {
	idx := 0
    scratchLen := len(framer.scratch)

	if scratchLen != 0 {
		// this is terrible for perf
		data = append(framer.scratch, data...)
		framer.scratch = make([]byte, 0)
	}

	count := 0
	for idx < len(data) {
		count++


		completed, nextEsc, style, err := nextAnsiChunk(data, idx)

		if !completed && framer.currentRow+1 != framer.rows {

            framer.scratch = make([]byte, len(data[idx:]))
            copy(framer.scratch, data[idx:])

			break
		}

		idx += nextEsc

		// errors happen when parsing non color commands
		// or there is just nothing that had any data when parsing
		if err != nil || style == nil {
			continue
		}

		color := RGBTo8BitColor(style.FgCol.Rgb)
		label := style.Label

		for _, char := range label {
			c := byte(char)
			if c == '\r' {
				continue
			}

			framer.produceFrame()

			if c == '\n' {
				framer.fillRemainingRow()
				framer.currentCol = 0
				framer.currentRow++
				continue
			}

			if framer.currentCol >= framer.cols {
				continue
			}

			framer.place(byte(color), c)
		}
		framer.produceFrame()
	}

	return len(data) - scratchLen, nil
}

func (a *Ansi8BitFramer) produceFrame() {
	if a.currentIdx == a.colorOffset {
		out := a.buffer

		a.ch <- Frame{
			Chars: out[:a.colorOffset],
			Color: out[a.colorOffset:],
		}

		a.buffer = make([]byte, a.rows*a.cols*2, a.rows*a.cols*2)
		a.currentIdx = 0
		a.currentCol = 0
		a.currentRow = 0
	}
}

func (a *Ansi8BitFramer) Frames() chan Frame {
	return a.ch
}