//
//  Lb2.swift
//  SampleBufferCompression
//
//  Created by Justin Allen on 3/30/24.
//

import AVFoundation

let COMPRESSED_AUDIO_SETTINGS: [String : Any] = [
    AVFormatIDKey: kAudioFormatMPEG4AAC,
    AVSampleRateKey: 44100,
    AVNumberOfChannelsKey: 2,
    AVEncoderBitRateKey: 128000
]

let PLAYBACK_AUDIO_SETTINGS: [String : Any] = [
    AVFormatIDKey: kAudioFormatLinearPCM,
    AVSampleRateKey: 44100,
    AVNumberOfChannelsKey: 2
]

class AudioTest {
    
    
    let outputEngine: OutputEngine
    let captureEngine: CaptureEngine
    
    init() {
        outputEngine = OutputEngine()
        captureEngine = CaptureEngine()
    }
    
    func startTest() {
        
        captureEngine.onBuffer = { buffer in
            //            let pcm = handleCompressedBuffer(buffer)
            self.outputEngine.handleBufferRecieved(buffer)
            
        }
        
        captureEngine.onData = { data in
            //            self.outputEngine.handleDataRecieved(data)
        }
        do {
            try captureEngine.startRecording()
            
            captureEngine.playAudioFile(named: "1-01 Great Balls Of Fire", withExtension: "m4a")
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
        
        let outputFormat = audioEngine.mainMixerNode.inputFormat(forBus:0)
        
        audioEngine.connect(audioPlayerNode, to: mixerNode, format: outputFormat)
        
        audioEngine.connect(mixerNode, to: audioEngine.mainMixerNode, format: outputFormat)
        compressedFormat = AVAudioFormat(settings:COMPRESSED_AUDIO_SETTINGS)
        
        let uncompressedFormat = mixerNode.inputFormat(forBus: 0)
        self.converter = AVAudioConverter(from: compressedFormat, to: uncompressedFormat)
        self.converter.reset()
        
        do {
            try audioEngine.start()
            audioPlayerNode.play()
        }
        catch {
            exit(-4)
        }
    }
    
    func handleBufferRecieved(_ cBuffer: AVAudioCompressedBuffer) {
        if let decomp = handleCompressedBuffer(cBuffer) {
            self.audioPlayerNode.scheduleBuffer(decomp)
        }
        
    }
    
    
    func handleCompressedBuffer(_ cBuffer: AVAudioCompressedBuffer) -> AVAudioPCMBuffer? {
        var outError: NSError? = nil
        let uncompressedFormat = mixerNode.inputFormat(forBus: 0)
        guard let uncompressedBuffer = AVAudioPCMBuffer(pcmFormat: uncompressedFormat, frameCapacity: AVAudioFrameCount(1000000)) else {
            print("Can't create uncompressed buffer")
            exit(-010)
        }
        
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus -> AVAudioBuffer? in
            outStatus.pointee = .haveData
            return cBuffer
        }
        
        let conversionResult = converter.convert(to: uncompressedBuffer, error: &outError) { inNumPackets, outStatus in
            return inputBlock(inNumPackets, outStatus)
        }
        
        if let error = outError {
            print("Conversion error: \(error.localizedDescription)")
            return nil
        }
        
        //        print(uncompressedBuffer)
        
        if conversionResult == .endOfStream {
            print("Conversion Result = endOfStream")
            countOfEndOfSteam += 1
            if countOfEndOfSteam > 10 {
                print("514: Reached 10 endOfStream results in a row.")
                exit(-6)
            }
        } else {
            countOfEndOfSteam = 0
        }
        
        return uncompressedBuffer
    }
    
    
    
    //    func handleCompressedBuffer(_ cBuffer: AVAudioCompressedBuffer) -> AVAudioPCMBuffer {
    //        var outError: NSError? = nil
    //        let uncompressedFormat = mixerNode.inputFormat(forBus: 0)
    //        if let uncompressedBuffer = AVAudioPCMBuffer(pcmFormat: uncompressedFormat, frameCapacity: AVAudioFrameCount(1000000) ) {
    //
    //            let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus -> AVAudioBuffer? in
    //                // Assuming sourceBuffer is your populated AVAudioCompressedBuffer
    //                outStatus.pointee = .haveData
    //                return cBuffer
    //            }
    //
    //
    //            let conversionResult = converter.convert(to: uncompressedBuffer, error: &outError) { inNumPackets, outStatus in
    //                return inputBlock(inNumPackets, outStatus)
    //            }
    //
    //            if conversionResult == .endOfStream {
    //                print(uncompressedBuffer)
    //                print("Conversion Result = endOfStream")
    //                countOfEndOfSteam += 1
    //                if countOfEndOfSteam > 10 {
    //                    print("Reached 10 endOfStream results in a row.")
    //                    exit(-6)
    //                }
    //
    //                // Exit the loop if we've reached the end of the stream
    //            }
    //            else {
    //                countOfEndOfSteam = 0
    //            }
    //            return uncompressedBuffer
    //        }
    //        else {
    //            print("Can't create uncompressed buffer")
    //            exit(-010)
    //        }
    //    }
    
    var countOfEndOfSteam = 0
    func handleDataRecieved(_ data: Data) {
        
        let packetCapacity = AVAudioPacketCount((data.count / 8) + 1)
        let maximumPacketSize = 32
        do {
            
            let decoder = JSONDecoder()
            let decodedData = try decoder.decode([Data].self, from: data)
            
            let decodedPacketDescriptionsData = decodedData[0]
            let decodedPacketDescriptions = try decoder.decode([PacketDescription].self, from: decodedPacketDescriptionsData)
            
            let decodedAudioData = decodedData[1]
            let compressedBuffer: AVAudioCompressedBuffer = AVAudioCompressedBuffer.init(format: compressedFormat, packetCapacity: packetCapacity, maximumPacketSize: maximumPacketSize)
            compressedBuffer.byteLength = UInt32(data.count)
            compressedBuffer.packetCount = AVAudioPacketCount(decodedPacketDescriptions.count)
            decodedAudioData.withUnsafeBytes {
                compressedBuffer.data.copyMemory(from: $0.baseAddress!, byteCount: data.count)
            }
            
            // Reassemble packet descriptions
            for (index, element) in decodedPacketDescriptions.enumerated() {
                compressedBuffer.packetDescriptions?[index] = AudioStreamPacketDescription(mStartOffset: element.mStartOffset,
                                                                                           mVariableFramesInPacket: UInt32(element.mVariableFramesInPacket),
                                                                                           mDataByteSize: UInt32(element.mDataByteSize))
            }
            
            print(compressedBuffer.packetDescriptions)
            
            //            self.audioPlayerNode.scheduleBuffer(compressedBuffer)
            if let uncompressed = handleCompressedBuffer(compressedBuffer) {
                print(uncompressed)
                self.audioPlayerNode.scheduleBuffer(uncompressed)
            }
            else {
                print("no uncompressed audio to play")
            }
            
        }
        catch {
            exit(-1)
        }
        
        
        //        print("Handle Data Recieved")
        //
        //        data.withUnsafeBytes { (bufferPointer) in
        //            let packetCapacity = AVAudioPacketCount((data.count / 8) + 1)
        //            // maxPacketSize was 8
        //            let compressedBufferLocal = AVAudioCompressedBuffer(format: converter.inputFormat, packetCapacity: packetCapacity, maximumPacketSize: 32)
        //
        //            let audioBuffer = compressedBufferLocal.audioBufferList.pointee.mBuffers
        //            guard let addr = bufferPointer.baseAddress else { return }
        //            guard let mdata = audioBuffer.mData else { return }
        //            compressedBufferLocal.byteLength = UInt32(data.count)
        //            //            compressedBuffer!.byteCapacity = UInt32(data.count) // this doesn't seem to be setter
        //            mdata.copyMemory(from: addr, byteCount: data.count)
        //            print(compressedBufferLocal)
        //
        //            if compressedBufferLocal.byteLength == 0 {
        //                print("line 232")
        //                exit(-4)
        //            }
        //            let frameCapacity = AVAudioFrameCount(exactly: 96_000)!
        //            print("Frame Capacity \(frameCapacity)")
        //            //            let uncompressedBuffer = AVAudioPCMBuffer(pcmFormat: uncompressedFormat, frameCapacity: frameCapacity )!
        //            //            print("converter formats \(converter.inputFormat) -> \(converter.outputFormat)")
        //
        //            let result = handleCompressedBuffer(compressedBufferLocal)
        //
        //
        //            //            print(compressedBufferLocal)
        //            //            print(uncompressedBuffer.frameCapacity)
        //            // Input block is called when the converter needs input
        //            //            uncompressedBuffer.frameLength = uncompressedBuffer.frameCapacity
        //
        //            //
        //            // Decompression loop
        //
        //            //
        //            //
        //            //            print(conversionResult)
        //            //            print(conversionResult.rawValue)
        //            //            print("error: \(outError)")
        //            //            print(uncompressedBuffer)
        //            //
        //
        //
        //            // INSTRUCTIONS: This is where it gets to 0 data to decompress.
        //
        //            //            // Check for errors
        //            //            if let error = outError {
        //            //                print("Error during conversion: \(error)")
        //            //                exit(-1)
        //            //            } else {
        //            //                print(uncompressedBuffer)
        //            //
        //            //                // Use the uncompressed audio
        //            //                let frameLength = uncompressedBuffer.frameLength
        //            //                if frameLength > 0 {
        //            //                    // Here you can use uncompressedBuffer, which now contains the uncompressed audio data
        //            //                    // For example, you might play it or save it to a file
        //            //                    self.audioPlayerNode.scheduleBuffer(uncompressedBuffer, completionHandler: {
        //            //
        //            //                    })
        //            //                    print("Playback rocks")
        //            //
        //            //                } else {
        //            //                    print("No data was decompressed.")
        //            //                    //                    exit(-5)
        //            //                }
        //            //            }
        //
        //        }
    }
    
}


struct PacketDescription: Codable {
    var mStartOffset: Int64
    var mVariableFramesInPacket: Int
    var mDataByteSize: Int
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
    public var onBuffer: ((AVAudioCompressedBuffer) -> Void)? = nil
    
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
        
        // trying 4 seems to work. pcmFormatFloat32
        print("Encoding with \(inputFormat.channelCount) channels, sampleRate: \(inputFormat.sampleRate).")
        let mixerFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputFormat.sampleRate, channels: inputFormat.channelCount, interleaved: false) // TODO: was one channels would this be 2 channels.
        
        
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
        
        //        var outDesc = AudioStreamBasicDescription()
        //        outDesc.mSampleRate = format.sampleRate
        //        outDesc.mChannelsPerFrame = format.channelCount
        //        outDesc.mFormatID = kAudioFormatMPEG4AAC
        //        outDesc.mFramesPerPacket = 1024 // AAC typically uses 1024 frames per packet
        //        // Other settings may need to be adjusted for AAC encoding
        
        print("Input bus count: \(tapNode.numberOfInputs)")
        
        let convertFormat = AVAudioFormat(settings: COMPRESSED_AUDIO_SETTINGS)!
        
        //        let convertFormat = AVAudioFormat(streamDescription: &outDesc)!
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
            
            self.onBuffer?(self.compressedBuffer!)
            
            var packetDescriptions = [PacketDescription]()
            
            for index in 0 ..< self.compressedBuffer!.packetCount {
                if let packetDescription = self.compressedBuffer!.packetDescriptions?[Int(index)] {
                    packetDescriptions.append(
                        PacketDescription(mStartOffset: packetDescription.mStartOffset,
                                          mVariableFramesInPacket: Int(packetDescription.mVariableFramesInPacket),
                                          mDataByteSize: Int(packetDescription.mDataByteSize)))
                }
            }
            
            let capacity = Int(self.compressedBuffer!.byteLength)
            let compressedBufferPointer = self.compressedBuffer!.data.bindMemory(to: UInt8.self, capacity: capacity)
            var compressedBytes: [UInt8] = [UInt8].init(repeating: 0, count: capacity)
            compressedBufferPointer.withMemoryRebound(to: UInt8.self, capacity: capacity) { sourceBytes in
                compressedBytes.withUnsafeMutableBufferPointer {
                    $0.baseAddress!.initialize(from: sourceBytes, count: capacity)
                }
            }
            
            let data = Data(compressedBytes)
            let encoder = JSONEncoder()
            do {
                let packetDescriptionsData = try encoder.encode(packetDescriptions)
                let combinedData = try encoder.encode([packetDescriptionsData, data])
                self.onData?(combinedData)
            }
            catch {
                exit(-2)
            }
            
            
            
            //            let audioData = Data(bytes: self.compressedBuffer!.data, count: Int(self.compressedBuffer!.byteLength))
            //            let packetDescriptions = Array(UnsafeBufferPointer(start: self.compressedBuffer!.packetDescriptions, count: Int(self.compressedBuffer!.packetCount)))
            //            // Assuming `encodedPacketDescriptions` is the result of encoding packet descriptions
            //            let combinedData = encodedPacketDescriptions + audioData
            //
            
            
            //            let audioBuffer = self.compressedBuffer!.audioBufferList.pointee.mBuffers
            //            if let mData = audioBuffer.mData {
            //                let length = Int(audioBuffer.mDataByteSize)
            //                let data: NSData = NSData(bytes: mData, length: length)
            //                // Do something with data
            //
            //                self.onData?(data as Data)
            //            }
            //            else {
            //                print("error")
            //            }
            
        })
        
        try engine.start()
        state = .recording
    }
    
    func playAudioFile(named fileName: String, withExtension fileExtension: String) {
        guard let fileURL = Bundle.main.url(forResource: fileName, withExtension: fileExtension) else {
            print("Audio file not found.")
            return
        }
        
        do {
            let audioFile = try AVAudioFile(forReading: fileURL)
            let playerNode = AVAudioPlayerNode()
            engine.attach(playerNode)
            
            let format = audioFile.processingFormat
            engine.connect(playerNode, to: mixerNode, format: format)
            
            try engine.start()
            playerNode.scheduleFile(audioFile, at: nil)
            playerNode.play()
        } catch {
            print("Error playing audio file: \(error.localizedDescription)")
        }
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