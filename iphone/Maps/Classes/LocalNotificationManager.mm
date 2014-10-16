
#import "LocalNotificationManager.h"
#import "MapsAppDelegate.h"
#import "Framework.h"
#import "AppInfo.h"
#import "LocationManager.h"
#import "MapViewController.h"
#import "Statistics.h"
#import "UIKitCategories.h"

#include "../../../storage/storage_defines.hpp"

#define DOWNLOAD_MAP_ACTION_NAME @"DownloadMapAction"

#define FLAGS_KEY @"DownloadMapNotificationFlags"
#define SHOW_INTERVAL (6 * 30 * 24 * 60 * 60) // six months

using namespace storage;

typedef void (^CompletionHandler)(UIBackgroundFetchResult);

@interface LocalNotificationManager () <CLLocationManagerDelegate, UIAlertViewDelegate>

@property (nonatomic) CLLocationManager * locationManager;
@property (nonatomic) TIndex countryIndex;
@property (nonatomic, copy) CompletionHandler downloadMapCompletionHandler;
@property (nonatomic) NSTimer * timer;

@end

@implementation LocalNotificationManager

+ (instancetype)sharedManager
{
  static LocalNotificationManager * manager;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    manager = [[self alloc] init];
  });
  return manager;
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations
{
  [self.timer invalidate];
  BOOL const inBackground = [UIApplication sharedApplication].applicationState == UIApplicationStateBackground;
  BOOL const onWiFi = [[AppInfo sharedInfo].reachability isReachableViaWiFi];
  if (inBackground && onWiFi)
  {
    Framework & f = GetFramework();
    CLLocation * lastLocation = [locations lastObject];
    TIndex const index = f.GetCountryIndex(MercatorBounds::FromLatLon(lastLocation.coordinate.latitude, lastLocation.coordinate.longitude));

    if (index.IsValid() && [self shouldShowNotificationForIndex:index])
    {
      TStatus const status = f.GetCountryStatus(index);
      if (status == TStatus::ENotDownloaded)
      {
        [self markNotificationShowingForIndex:index];

        UILocalNotification * notification = [[UILocalNotification alloc] init];
        notification.alertAction = L(@"download");
        notification.alertBody = L(@"download_map_notification");
        notification.soundName = UILocalNotificationDefaultSoundName;
        notification.userInfo = @{@"Action" : DOWNLOAD_MAP_ACTION_NAME, @"Group" : @(index.m_group), @"Country" : @(index.m_country), @"Region" : @(index.m_region)};

        UIApplication * application = [UIApplication sharedApplication];
        [application presentLocalNotificationNow:notification];
        [[Statistics instance] logEvent:@"'Download Map' Notification Scheduled"];
        // we don't need badges now
//        [application setApplicationIconBadgeNumber:[application applicationIconBadgeNumber] + 1];

        self.downloadMapCompletionHandler(UIBackgroundFetchResultNewData);
        return;
      }
    }
  }
  [[Statistics instance] logEvent:@"'Download Map' Notification Didn't Schedule" withParameters:@{@"WiFi" : @(onWiFi)}];
  self.downloadMapCompletionHandler(UIBackgroundFetchResultFailed);
}

- (void)markNotificationShowingForIndex:(TIndex)index
{
  NSMutableDictionary * flags = [[[NSUserDefaults standardUserDefaults] objectForKey:FLAGS_KEY] mutableCopy];
  if (!flags)
    flags = [[NSMutableDictionary alloc] init];

  flags[[self flagStringForIndex:index]] = [NSDate date];

  [[NSUserDefaults standardUserDefaults] setObject:flags forKey:FLAGS_KEY];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)shouldShowNotificationForIndex:(TIndex)index
{
  NSDictionary * flags = [[NSUserDefaults standardUserDefaults] objectForKey:FLAGS_KEY];
  NSDate * lastShowDate = flags[[self flagStringForIndex:index]];
  return !lastShowDate || [[NSDate date] timeIntervalSinceDate:lastShowDate] > SHOW_INTERVAL;
}

- (void)showDownloadMapNotificationIfNeeded:(void (^)(UIBackgroundFetchResult))completionHandler
{
  self.downloadMapCompletionHandler = completionHandler;
  self.timer = [NSTimer scheduledTimerWithTimeInterval:20 target:self selector:@selector(timerSelector:) userInfo:nil repeats:NO];
  if ([CLLocationManager locationServicesEnabled])
    [self.locationManager startUpdatingLocation];
  else
    completionHandler(UIBackgroundFetchResultFailed);
}

- (void)timerSelector:(id)sender
{
  // we have not got time to get location
  self.downloadMapCompletionHandler(UIBackgroundFetchResultFailed);
}

- (void)downloadCountryWithIndex:(TIndex)index
{
  //TODO: zoom in to country correctly to show download progress
  Framework & f = GetFramework();
  f.DownloadCountry(index, TMapOptions::EMapOnly);
  m2::RectD const rect = f.GetCountryBounds(index);
  double const lon = MercatorBounds::XToLon(rect.Center().x);
  double const lat = MercatorBounds::YToLat(rect.Center().y);
  f.ShowRect(lat, lon, 10);
}

- (void)processNotification:(UILocalNotification *)notification
{
  NSDictionary * ui = [notification userInfo];
  if ([ui[@"Action"] isEqualToString:DOWNLOAD_MAP_ACTION_NAME])
  {
    [[Statistics instance] logEvent:@"'Download Map' Notification Clicked"];
    [[MapsAppDelegate theApp].m_mapViewController.navigationController popToRootViewControllerAnimated:NO];

    TIndex const index = TIndex([ui[@"Group"] intValue], [ui[@"Country"] intValue], [ui[@"Region"] intValue]);
    [self downloadCountryWithIndex:index];
  }
}

- (void)showDownloadMapAlertIfNeeded
{
    // We should implement another version of alert

//  BOOL inForeground = [UIApplication sharedApplication].applicationState != UIApplicationStateBackground;
//  NSArray * flags = [[NSUserDefaults standardUserDefaults] objectForKey:FLAGS_KEY];
//  NSString * flag = [flags lastObject];
//  if (flag && inForeground)
//  {
//    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];
//    self.countryIndex = [self indexWithFlagString:flag];
//
//    Framework & f = GetFramework();
//    NSString * sizeString = [self sizeStringWithBytesCount:f.Storage().CountrySizeInBytes(self.countryIndex).second];
//    NSString * downloadText = [NSString stringWithFormat:@"%@ (%@)", L(@"download"), sizeString];
//    std::string const name = f.GetCountryName(self.countryIndex);
//    NSString * title = [NSString stringWithFormat:L(@"download_country_ask"), [NSString stringWithUTF8String:name.c_str()]];
//    UIAlertView * alertView = [[UIAlertView alloc] initWithTitle:title message:nil delegate:self cancelButtonTitle:L(@"cancel") otherButtonTitles:downloadText, nil];
//    [alertView show];
//  }
}

//- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
//{
//  if (buttonIndex != alertView.cancelButtonIndex)
//    [self downloadCountryWithIndex:self.countryIndex];
//}

//#define MB (1024 * 1024)
//
//- (NSString *)sizeStringWithBytesCount:(size_t)size
//{
//  if (size > MB)
//    return [NSString stringWithFormat:@"%ld %@", (size + 512 * 1024) / MB, L(@"mb")];
//  else
//    return [NSString stringWithFormat:@"%ld %@", (size + 1023) / 1024, L(@"kb")];
//}

- (NSString *)flagStringForIndex:(TIndex)index
{
  return [NSString stringWithFormat:@"%i_%i_%i", index.m_group, index.m_country, index.m_region];
}

- (TIndex)indexWithFlagString:(NSString *)flag
{
  NSArray * components = [flag componentsSeparatedByString:@"_"];
  if ([components count] == 3)
    return TIndex([components[0] intValue], [components[1] intValue], [components[2] intValue]);

  return TIndex();
}

- (CLLocationManager *)locationManager
{
  if (!_locationManager)
  {
    _locationManager = [[CLLocationManager alloc] init];
    _locationManager.delegate = self;
    _locationManager.distanceFilter = kCLLocationAccuracyThreeKilometers;
  }
  return _locationManager;
}

@end
