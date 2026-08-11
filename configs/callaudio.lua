-- Call audio - what a voice call SOUNDS like, on top of whichever resource carries it.
--
-- Carrying the voice is pma-voice's job: sd-phone puts both parties on a call channel and pma-voice
-- routes the audio between them. What pma-voice ships for that channel is a bare stereo pan with no
-- filtering at all, so a phone call sounds exactly like the other person standing next to you. The
-- lines below replace that with real telephone lines - band-limited, lightly driven signals that
-- read as "through a handset" - and swap between them as the call changes shape.
--
-- Each line is a GTA V radio-FX audio submix. Frequencies are Hz: the narrower the
-- FreqLow..FreqHigh band, the smaller and cheaper the speaker on the other end sounds. Fudge is
-- drive/saturation (0 = clean), and the Mod pair adds the faint metallic ring of a bad connection.
-- OutFreq* is the band the effect is allowed to output into, and wants to sit slightly wider than
-- the input band or the filter chokes the result.
return {
    -- Master switch. Off leaves pma-voice's own call submix alone, and nothing here is created.
    -- Note the server has to allow submixes at all: `setr voice_enableSubmix 1` (the default). With
    -- that off, pma-voice never applies a submix to anyone and none of this is audible.
    Enabled = true,

    -- Which line each situation uses. A call only ever sits on one of these; the priority when
    -- several apply at once is video > payphone > speaker > handset.
    Lines = {
        -- An ordinary cell call held to your ear. Roughly the classic 300-3400 Hz telephone band,
        -- opened up a touch at both ends so voices still carry weight.
        Handset = {
            FreqLow = 260.0, FreqHigh = 3600.0,
            OutFreqLow = 200.0, OutFreqHigh = 4200.0,
            Fudge = 0.15,
            ModFreq = 130.0, ModMix = 0.03,
            Volume = { Left = 1.0, Right = 1.0 },
        },

        -- Speakerphone: a tiny, hard-driven driver firing into a room. Narrower and grittier than
        -- the handset, which is what makes a player reach to turn it back off.
        Speaker = {
            FreqLow = 420.0, FreqHigh = 3200.0,
            OutFreqLow = 380.0, OutFreqHigh = 3600.0,
            Fudge = 0.30,
            ModFreq = 180.0, ModMix = 0.06,
            Volume = { Left = 1.0, Right = 1.0 },
        },

        -- FaceTime. A video call is wideband ("HD voice"), so this barely filters at all - the
        -- contrast with the handset line is the point.
        Video = {
            FreqLow = 120.0, FreqHigh = 7000.0,
            OutFreqLow = 100.0, OutFreqHigh = 7600.0,
            Fudge = 0.05,
            ModFreq = 0.0, ModMix = 0.0,
            Volume = { Left = 1.0, Right = 1.0 },
        },

        -- Street payphone: an analogue landline through a carbon handset. The narrowest and
        -- dirtiest of the four.
        Payphone = {
            FreqLow = 300.0, FreqHigh = 3000.0,
            OutFreqLow = 280.0, OutFreqHigh = 3400.0,
            Fudge = 0.35,
            ModFreq = 100.0, ModMix = 0.08,
            Volume = { Left = 1.0, Right = 1.0 },
        },
    },
}
