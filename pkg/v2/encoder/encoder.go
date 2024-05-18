package encoder

import (
	"github.com/theprimeagen/vim-with-me/pkg/v2/ascii_buffer"
	"github.com/theprimeagen/vim-with-me/pkg/v2/assert"
	"github.com/theprimeagen/vim-with-me/pkg/v2/huffman"
	"github.com/theprimeagen/vim-with-me/pkg/v2/net"
)

type EncodingFrame struct {
	Stride int

	Prev []byte
	Curr []byte

	Freq       ascii_buffer.Frequency
	Huff       *huffman.Huffman
	HuffBitLen int

	CurrQT ascii_buffer.Quadtree
	PrevQT ascii_buffer.Quadtree

	RLE ascii_buffer.AsciiRLE

	Out []byte
	Tmp []byte

	TmpLen int
	Len    int

	Encoding EncoderType
	Flags    byte
}

func (e *EncodingFrame) Into(data []byte, offset int) error {
    data[offset] = byte(e.Encoding)
    fn, ok := encodeInto[e.Encoding]
    assert.Assert(ok, "unknown encoding type", "encoding", e.Encoding)

    return fn(e, data, offset)
}

func (e *EncodingFrame) Type() byte {
	return byte(net.FRAME)
}

func (e *EncodingFrame) pushFrame(frame []byte) {
	e.Prev = e.Curr
	e.Curr = frame

	e.CurrQT.UpdateBuffer(e.Curr)
	if e.Prev != nil {
		e.PrevQT.UpdateBuffer(e.Prev)
	}
}

func newEncodingFrame(size int, params ascii_buffer.QuadtreeParam) *EncodingFrame {
	out := make([]byte, size, size)
	tmp := make([]byte, size, size)

	prevQt := ascii_buffer.Partition(out, params)
	currQt := ascii_buffer.Partition(out, params)
	return &EncodingFrame{
		Stride: params.Stride,

		Prev:   nil,
		PrevQT: prevQt,

		Curr:   nil,
		CurrQT: currQt,

		Freq: ascii_buffer.NewFreqency(),

		RLE: *ascii_buffer.NewAsciiRLE(),

		Out: out,
		Len: 0,

		Tmp:    tmp,
		TmpLen: 0,
	}
}

type EncodingCall func(frame *EncodingFrame) error

type Encoder struct {
	encodings []EncodingCall
	frames    []*EncodingFrame
	size      int
	params    ascii_buffer.QuadtreeParam
}

func NewEncoder(size int, treeParams ascii_buffer.QuadtreeParam) *Encoder {
	return &Encoder{
		encodings: make([]EncodingCall, 0),
		frames:    make([]*EncodingFrame, 0),
		size:      size,
		params:    treeParams,
	}
}

func (e *Encoder) AddEncoder(encoder EncodingCall) {
	e.encodings = append(e.encodings, encoder)
	e.frames = append(e.frames, newEncodingFrame(e.size, e.params))
}

func (e *Encoder) PushFrame(data []byte) *EncodingFrame {
	min := len(data)
	var outFrame *EncodingFrame = nil

	for i, encoder := range e.encodings {
		frame := e.frames[i]
		frame.pushFrame(data)

		err := encoder(frame)
		if err != nil {
			continue
		}

		if min > frame.Len {
			min = frame.Len
			outFrame = frame
		}
	}

	return outFrame
}