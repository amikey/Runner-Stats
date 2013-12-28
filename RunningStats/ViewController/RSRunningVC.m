//
//  RSFirstViewController.m
//  RunningStats
//
//  Created by Mr. Who on 12/20/13.
//  Copyright (c) 2013 hk. All rights reserved.
//

#import "RSRunningVC.h"

#define DISCARD_ALERT_TAG 0
#define SAVE_ALERT_TAG 1
#define MAP_REGION_SIZE 330

@interface RSRunningVC ()
@property (strong, nonatomic) IBOutlet MKMapView *map;
// TextField to display instant data
@property (strong, nonatomic) IBOutlet UILabel *timerLabel;
@property (strong, nonatomic) NSTimer *timer;
@property (strong, nonatomic) IBOutlet UILabel *currSpeedLabel;
@property (assign, nonatomic) CLLocationSpeed speed;
@property (strong, nonatomic) IBOutlet UILabel *distanceLabel;
@property (assign, nonatomic) CLLocationDistance distance;
@property (strong, nonatomic) IBOutlet UILabel *avgSpeedLabel;
@property (assign, nonatomic) CLLocationSpeed avgSpeed;

// Start a session
@property (strong, nonatomic) IBOutlet UIButton *startButton;
// Stop and discard a session
@property (strong, nonatomic) IBOutlet UIButton *stopButton;
// Stop and save a session
@property (strong, nonatomic) IBOutlet UIButton *saveButton;

@property (nonatomic, strong) RSRecordManager *recordManager;

@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) RSPath *path;
@property (nonatomic, strong) MKPolylineRenderer *pathRenderer;

@end

@implementation RSRunningVC
static unsigned int sessionSeconds = 0;

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self setUp];
}

- (void)setUp
{
    // locationManager
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.distanceFilter = 3.0f;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
    //可能需要防抖动
    currLocation = [self.locationManager location];
    // map
    self.map.showsUserLocation = YES;
    self.map.delegate = self;
    [self renewMapRegion];
    // path
    self.path = [[RSPath alloc] init];
    // UI
    self.saveButton.hidden = YES;
    self.stopButton.hidden = YES;
    // Create a record if not exist
    self.recordManager = [[RSRecordManager alloc] init];
    [self.recordManager createRecord];
    NSArray *allRecords = [self.recordManager getAllRecords];
    for (NSString *s in allRecords) {
        NSLog([s description]);
    }
}

# pragma mark Start Session
- (IBAction)startSession:(id)sender
{
    [self.locationManager startUpdatingLocation];
    while(![self.path saveFirstLocation:currLocation])
    {
        NSLog(@"Why");
        currLocation = [self.locationManager location];
    }
    
    if ([[self.map overlays] count] != 0) {
        [self.map removeOverlays:[self.map overlays]];
    }
    [self.map addOverlay:self.path];
    [self renewMapRegion];
    // start a timer
    [self startTimer];
    
    // UI
    self.startButton.hidden = YES;
    self.saveButton.hidden = NO;
    self.stopButton.hidden = NO;
}

- (void)startTimer
{
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(timerTick) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:self.timer forMode:NSDefaultRunLoopMode];
}

- (void)timerTick
{
    // Update sessionSeconds
    sessionSeconds += 1;
    // Update timerLabel
    [self updateTimerLabel];
}

- (void)updateTimerLabel
{
    self.timerLabel.text = [self timeFormatted:sessionSeconds];
}

- (NSString *)timeFormatted:(int)totalSeconds
{
    int seconds = totalSeconds % 60;
    int minutes = (totalSeconds / 60) % 60;
    int hours = totalSeconds / 3600;
    return [NSString stringWithFormat:@"%02d:%02d:%02d",hours, minutes, seconds];
}

#pragma mark Discard Session
- (IBAction)discardSession:(id)sender
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Discard?" message:@"Do you want to stop and discard this session?" delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Discard", nil];
    alert.tag = DISCARD_ALERT_TAG;
    [alert show];
}

- (IBAction)saveSession:(id)sender
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Save?" message:@"Do you want to stop and save this session?" delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Save", nil];
    alert.tag = SAVE_ALERT_TAG;
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView
clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == 1)
    {
        // First to stop session
        [self stopSession];
        // Discard session
        if (alertView.tag == DISCARD_ALERT_TAG)
        {
            // TO-DO: delete tmp files
            // Remove overlay, clear path
            [self.map removeOverlays:[self.map overlays]];
            [self.path clearContents];
        }
        // save session
        else if (alertView.tag == SAVE_ALERT_TAG)
        {
            // Save current session
            // TO-DO: save tmp files to disk
            // Remain all data
            // make it unable to zoom
            [self.path saveTmpAsValidRecord];
        }
    }
}

- (void)stopSession
{
    [self.locationManager stopUpdatingLocation];
    [self stopTimer];
    [self restoreUI];
}

- (void)restoreUI
{
    [self updateTimerLabel];
    self.currSpeedLabel.text = @"0.00";
    self.avgSpeedLabel.text = @"0.00";
    self.distanceLabel.text = @"0.00";
    // Restore buttons
    self.startButton.hidden = NO;
    self.stopButton.hidden = YES;
    self.saveButton.hidden = YES;
}

- (void)stopTimer
{
    if (self.timer) {
        [self.timer invalidate];
        self.timer = nil;
    }
    sessionSeconds = 0;
}



- (void)locationManager:(CLLocationManager *)manager
     didUpdateLocations:(NSArray *)locations
{
    CLLocation *newLocation = [locations lastObject];
    if ([self.path pointCount] == 0) {
        NSLog(@"WHY?");
        [self.path saveFirstLocation:currLocation];
    }
    if ((currLocation.coordinate.latitude != newLocation.coordinate.latitude) &&
        (currLocation.coordinate.longitude != newLocation.coordinate.longitude))
    {
        MKMapRect updateRect = [self.path addLocation:newLocation];
        
        if (!MKMapRectIsNull(updateRect))
        {
            // Update map and speed and distance textfields
            // Map
            // Compute the currently visible map zoom scale
            MKZoomScale currentZoomScale = (CGFloat)(self.map.bounds.size.width / self.map.visibleMapRect.size.width);
            // Find out the line width at this zoom scale and outset the updateRect by that amount
            CGFloat lineWidth = MKRoadWidthAtZoomScale(currentZoomScale);
            updateRect = MKMapRectInset(updateRect, -lineWidth, -lineWidth);
            // Ask the overlay view to update just the changed area.
            [self.pathRenderer setNeedsDisplayInMapRect:updateRect];
            // Update data
            self.distance = [self.path distance];
            self.speed = [self.path instantSpeed];
            self.avgSpeed = self.path.averageSpeed;
            // TO-DO: Save these data to tmp files!
            
            [self updateLabels];
            // Move map with user location
            currLocation = newLocation;
            [self renewMapRegion];
        }
    }
}

- (void)renewMapRegion
{
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(currLocation.coordinate, MAP_REGION_SIZE, MAP_REGION_SIZE);
    [self.map setRegion:region animated:YES];
}

- (void)updateLabels
{
    double tmp = 3.6 * self.speed;
    if (tmp > 10.0)
    {
        self.currSpeedLabel.text = [NSString stringWithFormat:@"%.1f", tmp];
    }
    else
    {
        self.currSpeedLabel.text = [NSString stringWithFormat:@"%.2f", tmp];
    }
    tmp = self.distance/1000;
    if (tmp > 10.0)
    {
        self.distanceLabel.text = [NSString stringWithFormat:@"%.1f", tmp];
    }
    else
    {
        self.distanceLabel.text = [NSString stringWithFormat:@"%.2f", tmp];
    }
    tmp = 3.6 * self.avgSpeed;
    if (tmp > 10.0)
    {
        self.avgSpeedLabel.text = [NSString stringWithFormat:@"%.1f", tmp];
    }
    else
    {
        self.avgSpeedLabel.text = [NSString stringWithFormat:@"%.2f", tmp];
    }
}

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView
            rendererForOverlay:(id <MKOverlay>)overlay
{
    if (!self.pathRenderer)
    {
        _pathRenderer = [[MKPolylineRenderer alloc] initWithOverlay:overlay];
        self.pathRenderer.strokeColor = [[UIColor alloc] initWithRed:66.0/255.0 green:204.0/255.0 blue:255.0/255.0 alpha:0.75];
        self.pathRenderer.lineWidth = 6.5;
    }
    return self.pathRenderer;
}


- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait;
}
@end
