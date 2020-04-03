#import "ViewController.h"
#import "SuperpoweredIOSAudioIO.h"
#include "Superpowered.h"
#include "SuperpoweredAdvancedAudioPlayer.h"
#include "SuperpoweredSimple.h"

// some HLS stream url-title pairs
static const char *urls[4] = {
    "https://cdn.fastlearner.media/bensound-rumble.mp3", "bensound-rumble.mp3","https://chtbl.com/track/18338/traffic.libsyn.com/secure/acquired/acquired_-_armrev_2.mp3?dest-id=376122","Acquired"
};

bool rePlay = true;

@implementation ViewController {
    UIView *bufferIndicator;
    CADisplayLink *displayLink;
    SuperpoweredIOSAudioIO *audioIO;
    Superpowered::AdvancedAudioPlayer *player;
    CGFloat sliderThumbWidth;
    unsigned int lastPositionSeconds, durationMs;
    NSInteger selectedRow;
}

@synthesize seekSlider, currentTime, duration, playPause, sources;

- (void)viewDidLoad {
    [super viewDidLoad];
    #ifdef __IPHONE_13_0
        if (@available(iOS 13, *)) self.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    #endif
    
    Superpowered::Initialize(
                             "ExampleLicenseKey-WillExpire-OnNextUpdate",
                             false, // enableAudioAnalysis (using SuperpoweredAnalyzer, SuperpoweredLiveAnalyzer, SuperpoweredWaveform or SuperpoweredBandpassFilterbank)
                             false, // enableFFTAndFrequencyDomain (using SuperpoweredFrequencyDomain, SuperpoweredFFTComplex, SuperpoweredFFTReal or SuperpoweredPolarFFT)
                             false, // enableAudioTimeStretching (using SuperpoweredTimeStretching)
                             false, // enableAudioEffects (using any SuperpoweredFX class)
                             true, // enableAudioPlayerAndDecoder (using SuperpoweredAdvancedAudioPlayer or SuperpoweredDecoder)
                             false, // enableCryptographics (using Superpowered::RSAPublicKey, Superpowered::RSAPrivateKey, Superpowered::hasher or Superpowered::AES)
                             false  // enableNetworking (using Superpowered::httpRequest)
                             );
    
    Superpowered::AdvancedAudioPlayer::setTempFolder([NSTemporaryDirectory() fileSystemRepresentation]);
    player = new Superpowered::AdvancedAudioPlayer(44100, 0);
    
    lastPositionSeconds = 0;
    selectedRow = 0;
    sliderThumbWidth = [seekSlider thumbRectForBounds:seekSlider.bounds trackRect:[seekSlider trackRectForBounds:seekSlider.bounds] value:0].size.width;

    bufferIndicator = [[UIView alloc] initWithFrame:CGRectZero];
    bufferIndicator.backgroundColor = [UIColor lightGrayColor];
    [self.view insertSubview:bufferIndicator belowSubview:seekSlider];

    displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onDisplayLink)];
    displayLink.frameInterval = 1;
    [displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];

    audioIO = [[SuperpoweredIOSAudioIO alloc] initWithDelegate:(id<SuperpoweredIOSAudioIODelegate>)self preferredBufferSize:12 preferredSamplerate:44100 audioSessionCategory:AVAudioSessionCategoryPlayback channels:2 audioProcessingCallback:audioProcessing clientdata:(__bridge void *)self];
    [audioIO start];

    [sources selectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] animated:NO scrollPosition:UITableViewScrollPositionTop];
    [self open:0];
}

- (void)dealloc {
    [displayLink invalidate];
    audioIO = nil;
    bufferIndicator = nil;
    delete player;
    //Superpowered::AdvancedAudioPlayer::clearTempFolder();
}

// Called periodically by the operating system's audio stack to provide audio output.
static bool audioProcessing(void *clientdata, float **inputBuffers, unsigned int inputChannels, float **outputBuffers, unsigned int outputChannels, unsigned int numberOfFrames, unsigned int samplerate, uint64_t hostTime) {
    __unsafe_unretained ViewController *self = (__bridge ViewController *)clientdata;
    self->player->outputSamplerate = samplerate;
    
    float interleavedBuffer[numberOfFrames * 2];
    bool notSilence = self->player->processStereo(interleavedBuffer, false, numberOfFrames);
    if (notSilence) Superpowered::DeInterleave(interleavedBuffer, outputBuffers[0], outputBuffers[1], numberOfFrames);
    return notSilence;
}

// Called periodically on every screen refresh, 60 fps.
- (void)onDisplayLink {
    // Check player events.
    switch (player->getLatestEvent()) {
        case Superpowered::PlayerEvent_Opened:
            player->play();
            break;
        case Superpowered::PlayerEvent_OpenFailed:
            NSLog(@"Open error %i: %s", player->getOpenErrorCode(), Superpowered::AdvancedAudioPlayer::statusCodeToString(player->getOpenErrorCode()));
            player->open(urls[0]);
            break;
        case Superpowered::PlayerEvent_None:
            //player->open(urls[0]);
            //player->play();
            //player->open(urls[0]);
            if (player->eofRecently()){
                player->setPosition(0, true, false);
                if (rePlay == true) {
                    [self open:2];
                }
            }
            break;
        case Superpowered::PlayerEvent_Opening:
            printf("opening");
            break;
        case Superpowered::PlayerEvent_ConnectionLost:
            printf("--------connection lost------");
            player->open(urls[0]);
            break;
        default:;
    };
    
    // On end of file return to the beginning and stop.
    if (player->eofRecently()) {
        player->setPosition(0, true, false);
        displayLink.frameInterval = 0;
    }
    
    if (durationMs != player->getDurationMs()) {
        durationMs = player->getDurationMs();
        
        if (durationMs == UINT_MAX) {
            duration.text = @"LIVE";
            seekSlider.hidden = YES;
        } else {
            duration.text = [NSString stringWithFormat:@"%02d:%02d", player->getDurationSeconds() / 60, player->getDurationSeconds() % 60];
            seekSlider.hidden = NO;
        };
        
        currentTime.hidden = playPause.hidden = NO;
    }
    
    // Update the buffering indicator.
    CGRect frame = seekSlider.frame;
    frame.size.width -= sliderThumbWidth;
    frame.origin.x += (player->getBufferedStartPercent() * frame.size.width) + (sliderThumbWidth * 0.5f);
    frame.size.width = (player->getBufferedEndPercent() - player->getBufferedStartPercent()) * frame.size.width;
    bufferIndicator.frame = frame;

    // Update the seek slider.
    unsigned int positionSeconds;
    if (seekSlider.tracking) positionSeconds = seekSlider.value * (float)player->getDurationSeconds();
    else {
        positionSeconds = player->getDisplayPositionSeconds();
        seekSlider.value = player->getDisplayPositionPercent();
    };
    NSLog(@"position Second : %d posision micro second: %f duration %d",player->getDisplayPositionSeconds(),player->getPositionMs(),player->getDurationMs());
    // Update the time display.
    if (lastPositionSeconds != positionSeconds) {
        lastPositionSeconds = positionSeconds;
        currentTime.text = [NSString stringWithFormat:@"%02d:%02d", positionSeconds / 60, positionSeconds % 60];
    };

    // Update the play/pause button.
    playPause.highlighted = player->isPlaying();
}

- (IBAction)onSeekSlider:(id)sender {
    player->seek(((UISlider *)sender).value);
}

- (IBAction)onDownloadStrategy:(id)sender {
//    switch (((UISegmentedControl *)sender).selectedSegmentIndex) {
//        case 1: player->HLSBufferingSeconds = 20; break; // Will not buffer more than 20 seconds ahead of the playback position.
//        case 2: player->HLSBufferingSeconds = 40; break; // Will not buffer more than 40 seconds ahead of the playback position.
//        case 3: player->HLSBufferingSeconds = Superpowered::AdvancedAudioPlayer::HLSDownloadEverything; break; // Will buffer everything after and before the playback position.
//        default: player->HLSBufferingSeconds = Superpowered::AdvancedAudioPlayer::HLSDownloadRemaining;        // Will buffer everything after the playback position.
//    };
    
}

- (IBAction)onPlayPause:(id)sender {
    player->togglePlayback();
}

- (IBAction)onSpeed:(id)sender {
    //player->playbackRate = ((UISwitch *)sender).on ? 2 : 1;
}

- (void)open:(NSInteger)row {
    currentTime.hidden = playPause.hidden = seekSlider.hidden = YES;
    duration.text = @"Loading...";
    player->open(urls[row]);
    //player->setTempFolder([NSTemporaryDirectory() fileSystemRepresentation]);
    //player->openHLS(urls[row]);
}

// The sources table is handled with these methods below:
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return sizeof(urls) / sizeof(urls[0]) / 2; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellID];
    cell.textLabel.text = [NSString stringWithUTF8String:urls[indexPath.row * 2 + 1]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row == selectedRow) return;
    selectedRow = indexPath.row;
    [self open:indexPath.row * 2];
}

@end
