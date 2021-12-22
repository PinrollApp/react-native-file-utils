#import <MobileCoreServices/MobileCoreServices.h>
#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <math.h>
#import "FileUtils.h"

@import Photos;

@implementation FileUtils

RCT_EXPORT_MODULE()

/**
 * Gets the duration of a video in seconds.
 * @param path - The video file path to get the duration of.
 * @returns The duration in seconds of the video file.
 */
RCT_EXPORT_METHOD(
                  getDuration:(NSString *)path
                  resolver: (RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject
                  )
{
    NSURL *referenceUrl = [NSURL URLWithString:path];
    
    if(referenceUrl != nil) {
        AVAsset *asset = [AVAsset assetWithURL:referenceUrl];
        Float64 duration = CMTimeGetSeconds(asset.duration);
        
        if (isnan(duration)) {
            reject(
                   @"INVALID_DURATION_ERROR",
                   @"The duration of the video file is either invalid or indefinite.",
                   nil
                   );
            return;
        }
        
        NSNumber *result = [NSNumber numberWithFloat:duration];
        resolve(result);
    } else {
        reject(
               @"GET_DURATION_MALFORMED_PATH_ERROR",
               @"The path provided is malformed. Unable to obtain a reference URL from the path.",
               nil
               );
        return;
    }
}

/**
 * Gets the MIME type of the file from the passed in URL. The file passed in can be a video or image file format.
 * @param path - The video or image file path to get the MIME type of.
 * @returns The MIME type string of the file from the passed URL.
 */
RCT_EXPORT_METHOD(
                  getMimeType:(NSString *)path
                  resolver: (RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject
                  )
{
    NSURL *referenceUrl = [NSURL URLWithString:path];
    CFStringRef fileExtension = (__bridge CFStringRef)[referenceUrl pathExtension];
    CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, fileExtension, NULL);
    CFStringRef MIMEType = UTTypeCopyPreferredTagWithClass(UTI, kUTTagClassMIMEType);
    
    if (UTI != nil) {
        CFRelease(UTI);
        resolve((NSString *)CFBridgingRelease(MIMEType));
    } else {
        reject(
               @"GET_MIME_TYPE_MALFORMED_PATH_ERROR",
               @"The path provided is malformed. Unable to obtain a reference URL from the path.",
               nil
               );
    }
}

/**
 * Gets the original date time of the video or image file based on the path passed in. The timestamp is retrieved from the Exif data on the
 * image or video file. Note: Either asset-libarary path or full file path may be passed in.
 * @param path - The video or image file path to get the timestamp of.
 * @param type - Either 'video' or 'image' so the method knows how to process the media file.
 * @returns The string timestamp of the image or video file.
 */
RCT_EXPORT_METHOD(
                  getTimestamp:(NSString *)path
                  fileType:(NSString *)type
                  resolver: (RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject
                  )
{
    // Path for getting exif from asset id if image or creation date for video
    if(![path hasPrefix:@"file:///"]) {
        PHAsset* asset = [PHAsset fetchAssetsWithLocalIdentifiers:@[path] options:nil].firstObject;
        PHContentEditingInputRequestOptions *editOptions = [[PHContentEditingInputRequestOptions alloc]init];
        editOptions.networkAccessAllowed = YES;
        
        // If image, use exif data
        if ([type isEqualToString:@"image"]) {
            [asset requestContentEditingInputWithOptions:editOptions completionHandler:^(PHContentEditingInput *contentEditingInput, NSDictionary *info) {
                CIImage *image = [CIImage imageWithContentsOfURL:contentEditingInput.fullSizeImageURL];
                NSDictionary *properties = image.properties;
                NSDictionary *exif = [properties objectForKey:(NSString *)kCGImagePropertyExifDictionary];
                NSDictionary *datetime = [exif objectForKey:(NSString *)kCGImagePropertyExifDateTimeOriginal];
                resolve(datetime);
                return;
            }];
        
        // If not an image, get last modified date
        } else {
            resolve(asset.creationDate);
            return;
        }

    // Path for getting exif from file path if image or creation date for video
    } else {
        NSString *prefixToRemove = @"file:///";
        NSString *pathWithoutFilePrefix = [path copy];
        if ([path hasPrefix:prefixToRemove])
            pathWithoutFilePrefix = [path substringFromIndex:[prefixToRemove length]];
        
        // If image, use exif data
        if ([type isEqualToString:@"image"]) {
            NSData* fileData = [NSData dataWithContentsOfFile:pathWithoutFilePrefix];
            CGImageSourceRef mySourceRef = CGImageSourceCreateWithData((CFDataRef)fileData, NULL);
            if (mySourceRef != NULL)
            {               
                NSDictionary *properties = (__bridge NSDictionary *)CGImageSourceCopyPropertiesAtIndex(mySourceRef,0,NULL);
                NSDictionary *exif = [properties objectForKey:(NSString *)kCGImagePropertyExifDictionary];
                NSDictionary *datetime = [exif objectForKey:(NSString *)kCGImagePropertyExifDateTimeOriginal];
                resolve(datetime);
                return;
            }
            
        // If not an image, get last modified date
        } else {
            NSError *error = nil;
            NSURL *referenceUrl = [NSURL URLWithString:path];
            NSDate *fileDate;
            [referenceUrl getResourceValue:&fileDate forKey:NSURLContentModificationDateKey error:&error];
            
            if (!error)
            {
                NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
                [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"];
                NSString *dateString = [dateFormatter stringFromDate:fileDate];
                
                resolve(dateString);
                return;
            }
            
            reject(
                   @"GET_TIMESTAMP_CONTENT_MODIFICATION_DATE_ERROR",
                   @"Error getting file data for file.",
                   error
                   );
        }
    }
}

/**
 * Gets the pixel dimensions, height and width (x,y), of the video file based on the file path passed in.
 * @param path - The video file path to get the dimensions of.
 * @returns The height and width (x,y), of the video or image in pixels.
 */
RCT_EXPORT_METHOD(
                  getVideoDimensions:(NSString *)path
                  resolver: (RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject
                  )
{
    NSURL *referenceUrl = [NSURL URLWithString:path];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:referenceUrl options:nil];
    NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    
    if ([tracks count] > 0) {
        AVAssetTrack *track = [tracks objectAtIndex:0];
        
        NSDictionary *dimensions = @{
              @"height":@(track.naturalSize.height),
              @"width":@(track.naturalSize.width),
              };
        
        resolve(dimensions);
        return;
    }

    NSDictionary *dimensions = @{
          @"height":@0,
          @"width":@0,
          };
    
    resolve(dimensions);
    return;
}

@end
