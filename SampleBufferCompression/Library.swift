//
//  Library.swift
//  SampleBufferCompression
//
//  Created by Justin Allen on 3/28/24.
//

import Foundation
import AVFoundation

class AudioTest {
    
    
    let outputEngine: OutputEngine
    let captureEngine: CaptureEngine
    
    init() {
        outputEngine = OutputEngine()
        captureEngine = CaptureEngine()
    }
    
    func startTest() {
        captureEngine.onData = { data in
            self.outputEngine.handleDataRecieved(data)
        }
        do {
            try captureEngine.startRecording()
        }
        catch {
            print(error)
            exit(-2)
        }
    }
    
}

class OutputEngine {
    let audioEngine: AVAudioEngine
    let audioPlayerNode: AVAudioPlayerNode
    private var mixerNode: AVAudioMixerNode!
    let compressedFormat: AVAudioFormat!
    
    var converter: AVAudioConverter!
    var compressedBuffer: AVAudioCompressedBuffer?
    
    init() {
        self.audioEngine = AVAudioEngine()
        self.audioPlayerNode = AVAudioPlayerNode()
        
        self.mixerNode = AVAudioMixerNode()
        self.audioEngine.attach(self.audioPlayerNode)
        self.audioEngine.attach(self.mixerNode)
        
        
        audioEngine.connect(audioPlayerNode, to: mixerNode, format: audioEngine.mainMixerNode.outputFormat(forBus:0))
        
        audioEngine.connect(mixerNode, to: audioEngine.mainMixerNode, format: audioEngine.mainMixerNode.outputFormat(forBus:0))
        
        //        uncompressedFormat = audioEngine.mainMixerNode.outputFormat(forBus: 0)
        
        var inputFormatDescription = AudioStreamBasicDescription()
        inputFormatDescription.mSampleRate = 44100.0 // Sample rate of the original audio
        inputFormatDescription.mChannelsPerFrame = 1 // Number of channels
        //        inputFormatDescription.mFormatID = kAudioFormatMPEG4AAC // FLAC format
        inputFormatDescription.mFormatID = kAudioFormatFLAC // FLAC format
        inputFormatDescription.mFramesPerPacket = 1152 // Frames per packet
        inputFormatDescription.mBitsPerChannel = 24 // Bit depth
        inputFormatDescription.mBytesPerPacket = 8 // Calculated based on other parameters
        compressedFormat = AVAudioFormat(streamDescription: &inputFormatDescription)!
        
        let format = self.audioEngine.mainMixerNode.inputFormat(forBus: 0)
        self.converter = AVAudioConverter(from: compressedFormat, to: format)
        self.converter.reset()
        
        
    }
    
    
    var countOfEndOfSteam = 0
    func handleDataRecieved(_ data: Data) {
        let uncompressedFormat = mixerNode.inputFormat(forBus: 0)
        //        let converter = AVAudioConverter(from: inputFormat, to: uncompressedFormat)!
        print("Handle Data Recieved")
        
        data.withUnsafeBytes { (bufferPointer) in
            let packetCapacity = AVAudioPacketCount((data.count / 8) + 1)
            // maxPacketSize was 8
            let compressedBufferLocal = AVAudioCompressedBuffer(format: converter.inputFormat, packetCapacity: packetCapacity, maximumPacketSize: 32)
            
            let audioBuffer = compressedBufferLocal.audioBufferList.pointee.mBuffers
            guard let addr = bufferPointer.baseAddress else { return }
            guard let mdata = audioBuffer.mData else { return }
            compressedBufferLocal.byteLength = UInt32(data.count)
            //            compressedBuffer!.byteCapacity = UInt32(data.count) // this doesn't seem to be setter
            mdata.copyMemory(from: addr, byteCount: data.count)
            print(compressedBufferLocal)
            
            if compressedBufferLocal.byteLength == 0 {
                print("line 232")
                exit(-4)
            }

            let sampleRate: Double = 44100
            let channels: AVAudioChannelCount = 2
            
            // Calculate frame capacity for 1 second of audio in this format.
            let frameCapacity = AVAudioFrameCount(sampleRate * Double(channels) * 1152 * 0.0001)
            //            let frameCapacity = AVAudioFrameCount((Int.max - 1) / 8)
            print("Frame Capacity \(frameCapacity)")
            let uncompressedBuffer = AVAudioPCMBuffer(pcmFormat: uncompressedFormat, frameCapacity: frameCapacity )!
            print("converter formats \(converter.inputFormat) -> \(converter.outputFormat)")
            
            self.converter = AVAudioConverter(from: compressedBufferLocal.format, to: uncompressedBuffer.format)!
            
            print(compressedBufferLocal)
            print(uncompressedBuffer.frameCapacity)
            // Input block is called when the converter needs input
            uncompressedBuffer.frameLength = uncompressedBuffer.frameCapacity
            let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus -> AVAudioBuffer? in
                //                return nil
                
                print("in \(inNumPackets) \(outStatus.pointee.rawValue)")
                //                outStatus.pointee = .haveData
                outStatus.pointee = .haveData
                print("called input block")
                
                print(compressedBufferLocal)
                return compressedBufferLocal // Provide the compressed buffer
            }
            
            // Decompression loop
            var outError: NSError? = nil
            
            
            let format = self.mixerNode.inputFormat(forBus: 0)
            self.converter = AVAudioConverter(from: compressedFormat, to: format)
            let conversionResult = converter.convert(to: uncompressedBuffer, error: &outError, withInputFrom: inputBlock)
            print(conversionResult)
            print(conversionResult.rawValue)
            
            if conversionResult == .endOfStream {
                print("Conversion Result = endOfStream")
                countOfEndOfSteam += 1
                if countOfEndOfSteam > 10 {
                    print("Reached 10 endOfStream results in a row.")
                    exit(-6)
                }
                
                // Exit the loop if we've reached the end of the stream
            }
            else {
                countOfEndOfSteam = 0
            }
            
            // INSTRUCTIONS: This is where it gets to 0 data to decompress.
            
            // Check for errors
            if let error = outError {
                print("Error during conversion: \(error)")
                exit(-1)
            } else {
                print(uncompressedBuffer)
                
                // Use the uncompressed audio
                let frameLength = uncompressedBuffer.frameLength
                if frameLength > 0 {
                    // Here you can use uncompressedBuffer, which now contains the uncompressed audio data
                    // For example, you might play it or save it to a file
                    self.audioPlayerNode.scheduleBuffer(uncompressedBuffer, completionHandler: {
                        
                    })
                    print("Playback rocks")
                    
                } else {
                    print("No data was decompressed.")
                    //                    exit(-5)
                }
            }
            
        }
    }
    
}





class CaptureEngine {
    enum RecordingState {
        case recording, paused, stopped
    }
    
    private var engine: AVAudioEngine!
    private var mixerNode: AVAudioMixerNode!
    
    private var state: RecordingState = .stopped
    
    var converter: AVAudioConverter!
    var compressedBuffer: AVAudioCompressedBuffer?
    
    public var onData: ((Data) -> Void)? = nil
    
    init() {
        engine = AVAudioEngine()
        mixerNode = AVAudioMixerNode()
        // Set volume to 0 to avoid audio feedback while recording.
        mixerNode.volume = 0
        //        mixerNode.pan = 1.0
        engine.attach(mixerNode)
        
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // mixer format doesn't seem to be doing both sides?
        // this works with 4 in the other demo, but not with 2 here. and it crashes.
#if os(macOS)
        // trying 4 seems to work. pcmFormatFloat32
        print("Encoding with \(inputFormat.channelCount) channels, sampleRate: \(inputFormat.sampleRate).")
        let mixerFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputFormat.sampleRate, channels: inputFormat.channelCount, interleaved: false) // TODO: was one channels would this be 2 channels.
#elseif os(iOS)
        let mixerFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputFormat.sampleRate, channels: 1, interleaved: false)
        // this seems to have to be channel count of 2, one actually makes it mono and play in both ears.
#endif
        
        engine.connect(inputNode, to: mixerNode, format: mixerFormat)
        
        let mainMixerNode = engine.mainMixerNode
        engine.connect(mixerNode, to: mainMixerNode, format: mixerFormat)
        
        // Prepare the engine in advance, in order for the system to allocate the necessary resources.
        engine.prepare()
    }
    
    
    
    func startRecording() throws {
        let tapNode: AVAudioNode = mixerNode
        //
        let format = tapNode.outputFormat(forBus: 0)
        var outDesc = AudioStreamBasicDescription()
        outDesc.mSampleRate = format.sampleRate
        outDesc.mChannelsPerFrame = 1
        outDesc.mFormatID = kAudioFormatFLAC
        
        let framesPerPacket: UInt32 = 1152
        outDesc.mFramesPerPacket = framesPerPacket
        outDesc.mBitsPerChannel = 8
        outDesc.mBytesPerPacket = 0
        
        print("Input bus count: \(tapNode.numberOfInputs)")
        
        let convertFormat = AVAudioFormat(streamDescription: &outDesc)!
        converter = AVAudioConverter(from: format, to: convertFormat)
        print("Recorder Converter \(converter.inputFormat) ----> \(converter.outputFormat)")
        
        // TODO: get the sample rate sent over to the client side on a per user basis.
        
        let packetSize: UInt32 = 16 // this was 8
        
        // was 4096
        tapNode.installTap(onBus: 0, bufferSize: 4096, format: format, block: {
            (buffer, time) in
            
            // super newest
            
            self.compressedBuffer = AVAudioCompressedBuffer(
                format: convertFormat,
                packetCapacity: packetSize,
                maximumPacketSize: self.converter.maximumOutputPacketSize
            )
            
            // input block is called when the converter needs input
            let inputBlock : AVAudioConverterInputBlock = { (inNumPackets, outStatus) -> AVAudioBuffer? in
                outStatus.pointee = AVAudioConverterInputStatus.haveData;
                return buffer; // fill and return input buffer
            }
            
            // Conversion loop
            var outError: NSError? = nil
            self.converter.convert(to: self.compressedBuffer!, error: &outError, withInputFrom: inputBlock)
            
            let audioBuffer = self.compressedBuffer!.audioBufferList.pointee.mBuffers
            if let mData = audioBuffer.mData {
                let length = Int(audioBuffer.mDataByteSize)
                let data: NSData = NSData(bytes: mData, length: length)
                // Do something with data
                
                self.onData?(data as Data)
            }
            else {
                print("error")
            }
            
        })
        
        try engine.start()
        state = .recording
    }
    
    
    func resumeRecording() throws {
        try engine.start()
        state = .recording
    }
    
    func pauseRecording() {
        engine.pause()
        state = .paused
    }
    
    func stopRecording() {
        mixerNode.removeTap(onBus: 0)
        engine.stop()
        converter?.reset()
        state = .stopped
    }
    
    
}
