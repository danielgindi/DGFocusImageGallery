//
//  DGFocusImageGallery.m
//  DGFocusImageGallery
//
//  Created by Daniel Cohen Gindi on 11/13/12.
//  Copyright (c) 2013 danielgindi@gmail.com. All rights reserved.
//
//  https://github.com/danielgindi/DGFocusImageGallery
//
//  The MIT License (MIT)
//  
//  Copyright (c) 2014 Daniel Cohen Gindi (danielgindi@gmail.com)
//  
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//  
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//  
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE. 
//  

#import "DGFocusImageGallery.h"
#import <CommonCrypto/CommonDigest.h>
#import <QuartzCore/QuartzCore.h>

#define DEFAULT_MAX_ASYNC_CONNECTIONS 8

@interface DGFocusImageGallery () <UIScrollViewDelegate, NSURLConnectionDelegate, UIGestureRecognizerDelegate>
{
    NSMutableArray *_downloadConnectionRequests;
    NSMutableArray *_downloadConnections;
    NSMutableArray *_downloadConnectionsFilePaths;
    NSMutableArray *_downloadConnectionsWriteHandles;
    NSMutableArray *_activeConnections;
    
    NSMutableArray *_imageViewContainers;
    NSMutableArray *_imageViews;
    NSMutableArray *_startedDownload;
    
    UIScrollView *_scrollView;
    
    NSUInteger _maxAsyncConnections;
    
    NSInteger _currentSelectedImage;
    
    BOOL _recognizingPinchOnImageContainer;
    
    CALayer *_defaultControlsViewBgLayer;
}

@property (nonatomic, strong) NSArray *galleryUrls;

@end

@implementation DGFocusImageGallery

static DGFocusImageGallery *s_DGFocusImageGallery_activeGallery;

- (id)init
{
    self = [super init];
    if (self)
    {
        _maxAsyncConnections = DEFAULT_MAX_ASYNC_CONNECTIONS;
        
        _startedDownload = [[NSMutableArray alloc] init];
        _downloadConnectionRequests = [NSMutableArray array];
        _downloadConnections = [NSMutableArray array];
        _downloadConnectionsFilePaths = [NSMutableArray array];
        _downloadConnectionsWriteHandles = [NSMutableArray array];
        _activeConnections = [NSMutableArray array];
        _imageViews = [NSMutableArray array];
        _imageViewContainers = [NSMutableArray array];
        _backgroundColorWhenFullyVisible = [UIColor colorWithWhite:0.f alpha:0.8f];
        
        self.allowImageRotation = YES;
    }
    return self;
}

- (void)dealloc
{
    [self cancelAllConnections];
    [self removeObserver:self forKeyPath:@"view.frame"];
}

- (void)loadView
{
    UIView *view = [[UIView alloc] init];
    
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.frame = [UIScreen mainScreen].applicationFrame;
    view.backgroundColor = [UIColor colorWithWhite:0.f alpha:0.f];
    
    self.view = view;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    UITapGestureRecognizer *globalTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(globalTapGestureRecognized:)];
    globalTapGestureRecognizer.numberOfTapsRequired = 1;
    globalTapGestureRecognizer.numberOfTouchesRequired = 1;
    [self.view addGestureRecognizer:globalTapGestureRecognizer];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if (!_scrollView)
    {
        _scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
        _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
        _scrollView.pagingEnabled = YES;
        _scrollView.delegate = self;
        _scrollView.showsHorizontalScrollIndicator = NO;
        _scrollView.scrollsToTop = NO;
        _scrollView.clipsToBounds = YES;
        _scrollView.contentSize = CGSizeMake(_scrollView.frame.size.width * _galleryUrls.count, _scrollView.frame.size.height);
        _scrollView.backgroundColor = [UIColor clearColor];
        _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        
        float xOffset = self.view.frame.size.width * ((float)_currentSelectedImage);
        _scrollView.contentOffset = CGPointMake(xOffset, 0.f);
    }
    
    [self.view addSubview:_scrollView];
    
    if (!_controlsView)
    {
        // Create the default controls view
        
        self.controlsView = [[UIView alloc] initWithFrame:CGRectMake(0.f, 0.f, self.view.frame.size.width, 80.f)];
        self.controlsView.translatesAutoresizingMaskIntoConstraints = NO;
        self.controlsView.backgroundColor = [UIColor clearColor];
        [self.controlsView addConstraint:[NSLayoutConstraint constraintWithItem:self.controlsView attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.f constant:80.f]];
        [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[view]|" options:0 metrics:nil views:@{@"view": self.controlsView}]];
        [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[view]" options:0 metrics:nil views:@{@"view": self.controlsView}]];
        
        CAGradientLayer *gradientLayer = [[CAGradientLayer alloc] init];
        gradientLayer.backgroundColor = [UIColor clearColor].CGColor;
        UIColor *firstColor = [UIColor colorWithWhite:2.f alpha:.1f];
        gradientLayer.colors = @[(id)firstColor.CGColor, (id)[firstColor colorWithAlphaComponent:0.f].CGColor];
        gradientLayer.locations = @[@.8f, @1.f];
        gradientLayer.frame = self.controlsView.layer.bounds;
        [self.controlsView.layer addSublayer:gradientLayer];
        _defaultControlsViewBgLayer = gradientLayer;
        
        UIImage *buttonImage = [UIImage imageNamed:@"DGFocusImageGallery-Close.png"];
        CGRect rc;
        rc.size = buttonImage.size;
        rc.origin.y = 10.f;
        rc.origin.x = self.controlsView.frame.size.width - rc.size.width - 10.f;
        
        UIButton *closeButton = [[UIButton alloc] initWithFrame:rc];
        closeButton.translatesAutoresizingMaskIntoConstraints = NO;
        [closeButton setBackgroundImage:buttonImage forState:UIControlStateNormal];
        [closeButton addTarget:self action:@selector(closeButtonTouchedUpInside:) forControlEvents:UIControlEventTouchDown];
        [self.controlsView addSubview:closeButton];
        
        [closeButton addConstraint:[NSLayoutConstraint constraintWithItem:closeButton attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.f constant:buttonImage.size.width]];
        [closeButton addConstraint:[NSLayoutConstraint constraintWithItem:closeButton attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.f constant:buttonImage.size.height]];
        
        [self.controlsView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:[button]-10-|" options:0 metrics:nil views:@{@"button": closeButton}]];
        [self.controlsView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-10-[button]" options:0 metrics:nil views:@{@"button": closeButton}]];
    }
    
    // Make sure it is setup to initial state
    self.controlsView.alpha = 0.f;
    self.controlsView.hidden = YES;
    
    // Make sure that the controls view is in the hierarchy, and in front
    if (self.controlsView.superview == self.view)
    {
        [self.view addSubview:self.controlsView];
    }
    else
    {
        [self.view bringSubviewToFront:self.controlsView];
    }
    
    if ([_delegate respondsToSelector:@selector(focusImageGalleryWillAppear:)])
    {
        [_delegate focusImageGalleryWillAppear:self];
    }
}

- (void)setControlsView:(UIView *)controlsView
{
    if (_controlsView == controlsView)
        return;
    
    if (_controlsView)
    {
        [_controlsView removeFromSuperview];
        _controlsView = nil;
    }
    
    _controlsView = controlsView;
    if (_controlsView)
    {
        _controlsView.alpha = 0.f;
        _controlsView.hidden = YES;
        
        if (self.isViewLoaded)
        {
            [self.view addSubview:self.controlsView];
            [self.view bringSubviewToFront:self.controlsView];
        }
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [self startDownloadForImageIndex:_currentSelectedImage];
    
    if ([_delegate respondsToSelector:@selector(focusImageGalleryDidAppear:)])
    {
        [_delegate focusImageGalleryDidAppear:self];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    if ([_delegate respondsToSelector:@selector(focusImageGalleryWillDisappear:)])
    {
        [_delegate focusImageGalleryWillDisappear:self];
    }
}


- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    
    [_scrollView removeFromSuperview];
    _scrollView = nil;
    
    if ([_delegate respondsToSelector:@selector(focusImageGalleryDidDisappear:)])
    {
        [_delegate focusImageGalleryDidDisappear:self];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (id)initWithGalleryUrls:(NSArray *)galleryUrls delegate:(id<DGFocusImageGalleryDelegate>)delegate
{
    self = [self init];
    if (self)
    {
        self.galleryUrls = galleryUrls;
        self.delegate = delegate;
    }
    return self;
}

+ (DGFocusImageGallery *)showInViewController:(UIViewController *)viewController
                                     delegate:(id<DGFocusImageGalleryDelegate>)delegate
                            withImageFromView:(UIView *)sourceView
                               andGalleryUrls:(NSArray *)galleryUrls
                         andCurrentImageIndex:(NSInteger)currentImage
                whenInitImageIsFitFromOutside:(BOOL)fitFromOutside
                                andCropAnchor:(DGFocusImageGalleryCropAnchor)cropAnchor
                           keepingAspectRatio:(BOOL)keepAspectRatio
{
    
    DGFocusImageGallery *vc = [[DGFocusImageGallery alloc] init];
    vc.galleryUrls = galleryUrls;
    vc.delegate = delegate;
    vc->_currentSelectedImage = currentImage;
    
    NSString *cachePath = [DGFocusImageGallery getLocalCachePathForUrl:(NSURL *)vc.galleryUrls[currentImage]];
    UIImage *viewImage = [UIImage imageWithContentsOfFile:cachePath];
    BOOL isFullImage = YES;
    
    if (!viewImage)
    {
        isFullImage = NO;
        UIGraphicsBeginImageContextWithOptions(sourceView.bounds.size, NO, UIScreen.mainScreen.scale);
        [sourceView.layer renderInContext:UIGraphicsGetCurrentContext()];
        viewImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    
    UIView *superview = viewController.view;
    
    /*if (viewController.navigationController)
    {
        superview = viewController.navigationController.view;
    }
    if ([NSStringFromClass(superview.class) isEqualToString:@"UILayoutContainerView"])
    {
        superview = superview.superview;
    }*/
    
    // Setup view's frame
    vc.view.frame = CGRectMake(0.f, 0.f, superview.frame.size.width, superview.frame.size.height);
    
    // Prepare for adding sub view controller, with proper notifications
    [viewController addChildViewController:vc];
    
    // Add viewcontroller's view
    [superview addSubview:vc.view];
    [superview addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[view]|" options:0 metrics:nil views:@{@"view": vc.view}]];
    [superview addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[view]|" options:0 metrics:nil views:@{@"view": vc.view}]];
    
    UIImageView *imageView = [vc createImageViewForImage:viewImage atIndex:currentImage];
    CGRect rcDest = imageView.frame;
    
    CGRect rcOrg = [sourceView.superview convertRect:sourceView.frame toView:superview];
    
    float scale = viewImage.scale / UIScreen.mainScreen.scale;
    rcOrg = [DGFocusImageGallery rectForWidth:viewImage.size.width * scale
                                    andHeight:viewImage.size.height * scale
                                      inFrame:rcOrg
                              keepAspectRatio:keepAspectRatio
                               fitFromOutside:fitFromOutside
                                   cropAnchor:cropAnchor];
    
    imageView.frame = rcOrg;
    imageView.alpha = 0.f;
    
    if (!isFullImage)
    {
        UIActivityIndicatorView *activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        activityIndicator.center = (CGPoint){rcOrg.size.width / 2.f, rcOrg.size.height / 2.f};
        [imageView addSubview:activityIndicator];
        [activityIndicator startAnimating];
        [vc startDownloadingImageAtUrl:vc.galleryUrls[currentImage]];
    }
    [vc->_startedDownload replaceObjectAtIndex:currentImage withObject:@(YES)];
    
    [UIView animateWithDuration:0.5f delay:0.f options:UIViewAnimationOptionCurveEaseOut animations:^{
        
        imageView.frame = rcDest;
        vc.view.backgroundColor = vc.backgroundColorWhenFullyVisible;
        imageView.alpha = 1.f;
        
    } completion:^(BOOL finished) {
        
        [vc didMoveToParentViewController:viewController];
        
    }];
    
    [vc addObserver:vc forKeyPath:@"view.frame" options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew context:NULL];
    
    s_DGFocusImageGallery_activeGallery = vc;
    
    return vc;
}

- (UIImageView *)createImageViewForImage:(UIImage *)image atIndex:(NSInteger)index
{
    float scale = image.scale / UIScreen.mainScreen.scale;
    CGSize destSize = [DGFocusImageGallery rectForWidth:image.size.width * scale
                                              andHeight:image.size.height * scale
                                                inFrame:self.view.frame
                                        keepAspectRatio:YES
                                         fitFromOutside:NO
                                             cropAnchor:DGFocusImageGalleryCropAnchorCenterCenter].size;
    
    CGRect rcDest = self.view.frame;
    UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
    rcDest.origin.x = (rcDest.size.width - destSize.width) / 2.f;
    rcDest.origin.y = (rcDest.size.height - destSize.height) / 2.f;
    rcDest.size = destSize;
    imageView.frame = rcDest;
    imageView.backgroundColor = [UIColor clearColor];
    imageView.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    
    UIView *imageViewContainer = [[UIView alloc] initWithFrame:CGRectMake(self.view.frame.origin.x + self.view.frame.size.width * ((float)index), 0.f, self.view.frame.size.width, self.view.frame.size.height)];
    imageViewContainer.backgroundColor = [UIColor clearColor];
    imageViewContainer.clipsToBounds = YES;
    
    [imageViewContainer addSubview:imageView];
    [self->_scrollView addSubview:imageViewContainer];
    
    [_imageViews replaceObjectAtIndex:index withObject:imageView];
    [_imageViewContainers replaceObjectAtIndex:index withObject:imageViewContainer];
    
    UIPinchGestureRecognizer *pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinchScaleGestureRecognizedOnImageContainer:)];
    pinchRecognizer.delegate = self;
    [imageViewContainer addGestureRecognizer:pinchRecognizer];
    UIPanGestureRecognizer *panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panGestureRecognizedOnImageContainer:)];
    panGestureRecognizer.delegate = self;
    panGestureRecognizer.maximumNumberOfTouches = 2;
    UIRotationGestureRecognizer *rotationGestureRecognizer = [[UIRotationGestureRecognizer alloc] initWithTarget:self action:@selector(rotationGestureRecognizedOnImageContainer:)];
    rotationGestureRecognizer.delegate = self;
    UITapGestureRecognizer *doubleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTapGestureRecognizedOnImageContainer:)];
    doubleTapGestureRecognizer.delegate = self;
    doubleTapGestureRecognizer.numberOfTapsRequired = 2;
    doubleTapGestureRecognizer.numberOfTouchesRequired = 1;
    [imageViewContainer addGestureRecognizer:pinchRecognizer];
    [imageViewContainer addGestureRecognizer:panGestureRecognizer];
    [imageViewContainer addGestureRecognizer:rotationGestureRecognizer];
    [imageViewContainer addGestureRecognizer:doubleTapGestureRecognizer];
    
    return imageView;
}

+ (DGFocusImageGallery *)activeGallery
{
    return s_DGFocusImageGallery_activeGallery;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
{
    return YES;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    CGRect rc = self.view.bounds;
    CGFloat w = rc.size.height;
    rc.size.height = rc.size.width;
    rc.size.width = w;
    rc.origin.x = rc.origin.y;
    [self layoutViewWithFrame:rc];
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (void)layoutViewWithFrame:(CGRect)frame
{
    if (_defaultControlsViewBgLayer)
    {
        _defaultControlsViewBgLayer.frame = _defaultControlsViewBgLayer.superlayer.bounds;
    }
    
    NSInteger currentImage = _scrollView.contentOffset.x / _scrollView.frame.size.width;
    _scrollView.frame = frame;
    _scrollView.contentSize = CGSizeMake(_scrollView.frame.size.width * _galleryUrls.count, _scrollView.frame.size.height);
    _scrollView.contentOffset = CGPointMake(_scrollView.frame.size.width * ((float)currentImage), 0.f);
    
    NSInteger idx = 0;
    for (UIView *view in _imageViewContainers)
    {
        if (view == (id)[NSNull null]) continue;
        
        view.frame = CGRectMake(((float)idx++) * _scrollView.frame.size.width, 0.f, _scrollView.frame.size.width, _scrollView.frame.size.height);
    }
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    
    [UIView animateWithDuration:0.15 delay:0.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        
        [self layoutViewWithFrame:self.view.frame];
        
    } completion:^(BOOL finished) {
    }];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath isEqualToString:@"view.frame"])
    {
        CGRect oldFrame = CGRectNull;
        CGRect newFrame = CGRectNull;
        if([change objectForKey:NSKeyValueChangeOldKey] != [NSNull null])
        {
            oldFrame = [[change objectForKey:NSKeyValueChangeOldKey] CGRectValue];
        }
        if([change objectForKey:NSKeyValueChangeNewKey] != [NSNull null])
        {
            newFrame = [[change objectForKey:NSKeyValueChangeNewKey] CGRectValue];
        }
        if (CGRectIsNull(oldFrame) || !CGRectEqualToRect(oldFrame, newFrame))
        {
            [self layoutViewWithFrame:newFrame];
        }
    }
}

- (void)closeAndRemoveTempFile:(NSString *)filePath writeHandle:(NSFileHandle *)fileWriteHandle
{
    if (fileWriteHandle)
    {
        [fileWriteHandle closeFile];
        fileWriteHandle = nil;
    }
    if (filePath)
    {
        [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
        filePath = nil;
    }
}

- (void)setGalleryUrls:(NSArray *)galleryUrls
{
    NSMutableArray *urls = [NSMutableArray array];
    for (NSObject *obj in galleryUrls)
    {
        if (![obj isKindOfClass:[NSURL class]])
        {
            [urls addObject:[DGFocusImageGallery normalizedUrlForUrl:[NSURL URLWithString:(NSString *)obj]]];
        }
        else
        {
            [urls addObject:[DGFocusImageGallery normalizedUrlForUrl:(NSURL *)obj]];
        }
    }
    _galleryUrls = urls;
    
    [_imageViews removeAllObjects];
    [_imageViewContainers removeAllObjects];
    [_startedDownload removeAllObjects];
    
    for (NSUInteger i = 0, count = _galleryUrls.count; i < count; i++)
    {
        [_imageViews addObject:[NSNull null]];
        [_imageViewContainers addObject:[NSNull null]];
        [_startedDownload addObject:[NSNull null]];
    }
}

- (void)hide
{
    [self willMoveToParentViewController:nil];
    
    [UIView animateWithDuration:0.15 delay:0.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        
        self.view.alpha = 0.f;
        
    } completion:^(BOOL finished) {
        
        [self.view removeFromSuperview];
        [self cancelAllConnections];
        [self removeFromParentViewController];
        
        if (s_DGFocusImageGallery_activeGallery == self)
        {
            s_DGFocusImageGallery_activeGallery = nil; // Releease
        }
        
    }];
}

#pragma mark - Actions

- (void)closeButtonTouchedUpInside:(id)sender
{
    [self hide];
}

- (void)globalTapGestureRecognized:(UITapGestureRecognizer *)recognizer
{
    BOOL show = self.controlsView.alpha == 0.f;
    
    BOOL cancel = NO;
    
    if (show)
    {
        if ([_delegate respondsToSelector:@selector(focusImageGalleryWillShowControls:)])
        {
            cancel = ![_delegate focusImageGalleryWillShowControls:self];
        }
    }
    else
    {
        if ([_delegate respondsToSelector:@selector(focusImageGalleryWillHideControls:)])
        {
            cancel = ![_delegate focusImageGalleryWillHideControls:self];
        }
    }
    
    if (cancel)
    {
        return;
    }
    
    [UIView animateWithDuration:0.15 delay:0.0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        
        if (show)
        {
            self.controlsView.hidden = NO;
            self.controlsView.alpha = 1.f;
        }
        else
        {
            self.controlsView.alpha = 0.f;
        }
        
    } completion:^(BOOL finished) {
        
        if (self.controlsView.alpha == 0.f)
        {
            self.controlsView.hidden = YES;
        }
        
    }];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return [_imageViewContainers containsObject:gestureRecognizer.view] && [_imageViewContainers containsObject:otherGestureRecognizer.view];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    if ([gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]])
    {
        if ([_imageViewContainers containsObject:gestureRecognizer.view])
        {
            return _recognizingPinchOnImageContainer;
        }
    }
    return YES;
}

#pragma mark - Utilities

- (void)adjustAnchorPointForGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer withView:(UIView *)view
{
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan)
    {
        CGPoint locationInView = [gestureRecognizer locationInView:view];
        CGPoint locationInSuperview = [gestureRecognizer locationInView:view.superview];
        
        view.layer.anchorPoint = CGPointMake(locationInView.x / view.bounds.size.width, locationInView.y / view.bounds.size.height);
        view.center = locationInSuperview;
    }
}

- (void)panGestureRecognizedOnImageContainer:(UIPanGestureRecognizer *)gestureRecognizer
{
    UIImageView *imageView = nil;
    for (int j = 0; j < gestureRecognizer.view.subviews.count; j++)
    {
        imageView = gestureRecognizer.view.subviews[j];
        if ([imageView isKindOfClass:[UIImageView class]]) break;
        imageView = nil;
    }
    
    if (imageView)
    {
        [self adjustAnchorPointForGestureRecognizer:gestureRecognizer withView:imageView];
        
        if (gestureRecognizer.state == UIGestureRecognizerStateBegan || gestureRecognizer.state == UIGestureRecognizerStateChanged)
        {
            CGPoint translation = [gestureRecognizer translationInView:[imageView superview]];
            
            imageView.center = CGPointMake(imageView.center.x + translation.x, imageView.center.y + translation.y);
            [gestureRecognizer setTranslation:CGPointZero inView:imageView.superview];
        }
    }
}

- (void)rotationGestureRecognizedOnImageContainer:(UIRotationGestureRecognizer *)gestureRecognizer
{
    UIImageView *imageView = nil;
    for (int j = 0; j < gestureRecognizer.view.subviews.count; j++)
    {
        imageView = gestureRecognizer.view.subviews[j];
        if ([imageView isKindOfClass:[UIImageView class]]) break;
        imageView = nil;
    }
    
    if (imageView)
    {
        if (!self.allowImageRotation) return;
        
        [self adjustAnchorPointForGestureRecognizer:gestureRecognizer withView:imageView];
        
        if (gestureRecognizer.state == UIGestureRecognizerStateBegan || gestureRecognizer.state == UIGestureRecognizerStateChanged)
        {
            imageView.transform = CGAffineTransformRotate(imageView.transform, gestureRecognizer.rotation);
            [gestureRecognizer setRotation:0];
        }
    }
}

- (void)pinchScaleGestureRecognizedOnImageContainer:(UIPinchGestureRecognizer *)gestureRecognizer
{
    UIImageView *imageView = nil;
    for (int j = 0; j < gestureRecognizer.view.subviews.count; j++)
    {
        imageView = gestureRecognizer.view.subviews[j];
        if ([imageView isKindOfClass:[UIImageView class]]) break;
        imageView = nil;
    }
    
    if (imageView)
    {
        [self adjustAnchorPointForGestureRecognizer:gestureRecognizer withView:imageView];
        
        if (gestureRecognizer.state == UIGestureRecognizerStateBegan || gestureRecognizer.state == UIGestureRecognizerStateChanged)
        {
            _recognizingPinchOnImageContainer = YES;
            
            imageView.transform = CGAffineTransformScale(imageView.transform, gestureRecognizer.scale, gestureRecognizer.scale);
            [gestureRecognizer setScale:1];
        }
        else if (gestureRecognizer.state == UIGestureRecognizerStateEnded)
        {
            CGAffineTransform transform = imageView.transform;
            
            if (sqrt(transform.a*transform.a+transform.c*transform.c) < 1.f ||
                sqrt(transform.b*transform.b+transform.d*transform.d) < 1.f)
            {
                [UIView animateWithDuration:0.15f delay:0.f options:UIViewAnimationOptionCurveEaseOut animations:^{
                    
                    imageView.transform = CGAffineTransformIdentity;
                    imageView.layer.anchorPoint = CGPointMake(0.5f, 0.5f);
                    imageView.center = CGPointMake(imageView.superview.bounds.size.width / 2.f, imageView.superview.bounds.size.height / 2.f);
                    
                    
                } completion:^(BOOL finished) {
                    
                }];
            }
            
            _recognizingPinchOnImageContainer = NO;
        }
    }
}

- (void)doubleTapGestureRecognizedOnImageContainer:(UITapGestureRecognizer *)gestureRecognizer
{
    UIImageView *imageView = nil;
    for (int j = 0; j < gestureRecognizer.view.subviews.count; j++)
    {
        imageView = gestureRecognizer.view.subviews[j];
        if ([imageView isKindOfClass:[UIImageView class]]) break;
        imageView = nil;
    }
    
    if (imageView)
    {
        [UIView animateWithDuration:0.3f delay:0.f options:UIViewAnimationOptionCurveEaseIn animations:^{
            
            if (CGAffineTransformEqualToTransform(imageView.transform, CGAffineTransformIdentity))
            {
                imageView.transform = CGAffineTransformMakeScale(2.f, 2.f);
                imageView.layer.anchorPoint = CGPointMake(0.5f, 0.5f);
                imageView.center = CGPointMake(imageView.superview.bounds.size.width / 2.f, imageView.superview.bounds.size.height / 2.f);
            }
            else
            {
                imageView.transform = CGAffineTransformIdentity;
                imageView.layer.anchorPoint = CGPointMake(0.5f, 0.5f);
                imageView.center = CGPointMake(imageView.superview.bounds.size.width / 2.f, imageView.superview.bounds.size.height / 2.f);
            }
            
        } completion:^(BOOL finished) {
            
        }];
    }
}

+ (CGRect)rectForWidth:(CGFloat)cx
             andHeight:(CGFloat)cy
               inFrame:(CGRect)parentBox
       keepAspectRatio:(BOOL)keepAspectRatio
        fitFromOutside:(BOOL)fitFromOutside
            cropAnchor:(DGFocusImageGalleryCropAnchor)cropAnchor
{
    CGRect box = parentBox;
    if (keepAspectRatio)
    {
        CGFloat ratio = cy == 0 ? 1 : (cx / cy);
        CGFloat newRatio = parentBox.size.height == 0 ? 1 : (parentBox.size.width / parentBox.size.height);
        
        if ((newRatio > ratio && !fitFromOutside) ||
            (newRatio < ratio && fitFromOutside))
        {
            box.size.height = parentBox.size.height;
            box.size.width = box.size.height * ratio;
        }
        else if ((newRatio > ratio && fitFromOutside) ||
                 (newRatio < ratio && !fitFromOutside))
        {
            box.size.width = parentBox.size.width;
            box.size.height = box.size.width / ratio;
        }
        else
        {
            box.size.width = parentBox.size.width;
            box.size.height = parentBox.size.height;
        }
        
        if (fitFromOutside)
        {
            switch (cropAnchor)
            {
                default:
                case DGFocusImageGalleryCropAnchorCenterCenter:
                    box.origin.x = (parentBox.size.width - box.size.width) / 2.f;
                    box.origin.y = (parentBox.size.height - box.size.height) / 2.f;
                    break;
                case DGFocusImageGalleryCropAnchorCenterLeft:
                    box.origin.x = 0.f;
                    box.origin.y = (parentBox.size.height - box.size.height) / 2.f;
                    break;
                case DGFocusImageGalleryCropAnchorCenterRight:
                    box.origin.x = parentBox.size.width - box.size.width;
                    box.origin.y = (parentBox.size.height - box.size.height) / 2.f;
                    break;
                case DGFocusImageGalleryCropAnchorTopCenter:
                    box.origin.x = (parentBox.size.width - box.size.width) / 2.f;
                    box.origin.y = 0.f;
                    break;
                case DGFocusImageGalleryCropAnchorTopLeft:
                    box.origin.x = 0.f;
                    box.origin.y = 0.f;
                    break;
                case DGFocusImageGalleryCropAnchorTopRight:
                    box.origin.x = parentBox.size.width - box.size.width;
                    box.origin.y = 0.f;
                    break;
                case DGFocusImageGalleryCropAnchorBottomCenter:
                    box.origin.x = (parentBox.size.width - box.size.width) / 2.f;
                    box.origin.y = parentBox.size.height - box.size.height;
                    break;
                case DGFocusImageGalleryCropAnchorBottomLeft:
                    box.origin.x = 0.f;
                    box.origin.y = parentBox.size.height - box.size.height;
                    break;
                case DGFocusImageGalleryCropAnchorBottomRight:
                    box.origin.x = parentBox.size.width - box.size.width;
                    box.origin.y = parentBox.size.height - box.size.height;
                    break;
            }
        }
        else
        {
            box.origin.x = (parentBox.size.width - box.size.width) / 2.f;
            box.origin.y = (parentBox.size.height - box.size.height) / 2.f;
        }
    }
    else
    {
        box.origin.x = 0.f;
        box.origin.y = 0.f;
        box.size = parentBox.size;
    }
    
    box.origin.x += parentBox.origin.x;
    box.origin.y += parentBox.origin.y;
    
    return box;
}

- (NSString *)newTempFilePath
{
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    CFStringRef uuidStr = CFUUIDCreateString(NULL, uuid);
    
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"image-loader-%@", uuidStr]];
    
    CFRelease(uuidStr);
    CFRelease(uuid);
    
    return path;
}

- (NSFileHandle *)fileHandleToANewTempFile:(out NSString **)filePath
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *tempFilePath = self.newTempFilePath;
    int tries = 3;
    BOOL success = [fileManager createFileAtPath:tempFilePath contents:nil attributes:nil];
    while (!success && --tries)
    {
        tempFilePath = self.newTempFilePath;
        success = [fileManager createFileAtPath:tempFilePath contents:nil attributes:nil];
    }
    
    if (success)
    {
        if (filePath)
        {
            *filePath = tempFilePath;
        }
        return [NSFileHandle fileHandleForWritingAtPath:tempFilePath];
    }
    
    return nil;
}

+ (NSURL *)normalizedUrlForUrl:(NSURL *)url
{
    if (url.isFileURL)
    {
        if (UIScreen.mainScreen.scale == 2.f && ![[[url lastPathComponent] stringByDeletingPathExtension] hasSuffix:@"@2x"])
        {
            NSString *path = [[url path] stringByDeletingPathExtension];
            path = [path stringByAppendingString:@"@2x"];
            if (url.pathExtension.length || [[url lastPathComponent] hasSuffix:@"."])
            {
                path = [path stringByAppendingPathExtension:url.pathExtension];
            }
            if ([[NSFileManager defaultManager] fileExistsAtPath:path])
            {
                return [[NSURL alloc] initFileURLWithPath:path];
            }
        }
    }
    return url;
}

#pragma mark - Caching stuff

+ (NSString *)getLocalCachePathForUrl:(NSURL *)url
{
    if (!url) return nil; // Silence Xcode's Analyzer
    
    // an alternative to the NSTemporaryDirectory
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *path = paths.count ? paths[0] : [NSHomeDirectory() stringByAppendingString:@"/Library/Caches"];
    path = [path stringByAppendingPathComponent:@"dg-image-loader"];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:path])
    {
        NSError *error = nil;
        if (![fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error])
        {
            NSLog(@"Can't create cache folder, error: %@", error);
            return nil;
        }
    }
    
    const char *urlStr = url.absoluteString.UTF8String;
    unsigned char md5result[16];
    CC_MD5(urlStr, (CC_LONG)strlen(urlStr), md5result); // This is the md5 call
    path = [path stringByAppendingPathComponent:
            [NSString stringWithFormat:
             @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
             md5result[0], md5result[1], md5result[2], md5result[3],
             md5result[4], md5result[5], md5result[6], md5result[7],
             md5result[8], md5result[9], md5result[10], md5result[11],
             md5result[12], md5result[13], md5result[14], md5result[15]
             ]];
    
    NSString *fn = url.lastPathComponent.lowercaseString;
    
    BOOL doubleScale = [[fn stringByDeletingPathExtension] hasSuffix:@"@2x"];
    
    if (doubleScale)
    {
        path = [path stringByAppendingString:@"@2x"];
    }
    
    if (fn.pathExtension.length)
    {
        path = [path stringByAppendingPathExtension:fn.pathExtension];
    }
    
    return path;
}

#pragma mark - NSURLConnectionDelegate

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
	if ([response respondsToSelector:@selector(statusCode)])
	{
		NSInteger statusCode = [((NSHTTPURLResponse *)response) statusCode];
		if (statusCode != 200)
		{
			[self connection:connection didFailWithError:nil];
		}
	}
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)incrementalData
{
    @synchronized(_downloadConnections)
    {
        [(NSFileHandle *)_downloadConnectionsWriteHandles[[_downloadConnections indexOfObject:connection]] writeData:incrementalData];
    }
    
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    @synchronized(_downloadConnections)
    {
        [connection cancel];
        
        NSInteger connectionIndex = [_downloadConnections indexOfObject:connection];
        [_downloadConnections removeObjectAtIndex:connectionIndex];
        [_downloadConnectionRequests removeObjectAtIndex:connectionIndex];
        
        [(NSFileHandle *)_downloadConnectionsWriteHandles[connectionIndex] closeFile];
        [[NSFileManager defaultManager] removeItemAtPath:_downloadConnectionsFilePaths[connectionIndex] error:nil];
        
        [_downloadConnectionsWriteHandles removeObjectAtIndex:connectionIndex];
        [_downloadConnectionsFilePaths removeObjectAtIndex:connectionIndex];
    }
    [self continueConnectionQueue];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    NSString *imageFilePath;
    NSURL *currentUrl;
    @synchronized(_downloadConnections)
    {
        NSInteger connectionIndex = [_downloadConnections indexOfObject:connection];
        
        [(NSFileHandle *)_downloadConnectionsWriteHandles[connectionIndex] closeFile];
        imageFilePath = _downloadConnectionsFilePaths[connectionIndex];
        
        currentUrl = ((NSURLRequest *)_downloadConnectionRequests[connectionIndex]).URL;
        [_downloadConnections removeObjectAtIndex:connectionIndex];
        [_downloadConnectionRequests removeObjectAtIndex:connectionIndex];
        [_downloadConnectionsWriteHandles removeObjectAtIndex:connectionIndex];
        [_downloadConnectionsFilePaths removeObjectAtIndex:connectionIndex];
    }
    [self continueConnectionQueue];
    
	if (imageFilePath.length)
	{
        __block __typeof(self) _self = self;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            
            NSInteger imageIndex = [_self->_galleryUrls indexOfObject:currentUrl];
            
            NSString *cachePath = [DGFocusImageGallery getLocalCachePathForUrl:currentUrl];
            [[NSFileManager defaultManager] moveItemAtPath:imageFilePath toPath:cachePath error:nil];
            
            UIView *currentImageView = _imageViews[imageIndex];
            UIImage *viewImage = [UIImage imageWithContentsOfFile:cachePath];
            
            if (viewImage)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    
                    UIImageView *imageView = [self createImageViewForImage:viewImage atIndex:imageIndex];
                    
                    CGRect destFrame = imageView.frame;
                    CGRect srcFrame = currentImageView ? destFrame : [currentImageView.layer.presentationLayer frame];
                    
                    imageView.alpha = 0.f;
                    imageView.frame = srcFrame;
                
                    [UIView animateWithDuration:0.15 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
                        
                        imageView.alpha = 1.f;
                        
                        if (!CGRectEqualToRect(srcFrame, destFrame))
                        {
                            imageView.frame = destFrame;
                        }
                        
                    } completion:^(BOOL finished) {
                        [currentImageView removeFromSuperview];
                    }];
                    
                });
            }
            
        });
    }
}

#pragma mark - Connection control

- (void)startDownloadingImageAtUrl:(NSURL *)url
{
    @synchronized(_downloadConnections)
    {
        NSURLRequest *urlRequest = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:60.0];
        NSURLConnection *urlConnection = [[NSURLConnection alloc] initWithRequest:urlRequest delegate:self startImmediately:NO];
        
        [_downloadConnectionRequests addObject:urlRequest];
        [_downloadConnections addObject:urlConnection];
        
        NSString *filePath;
        NSFileHandle *fileWriteHandler = [self fileHandleToANewTempFile:&filePath];
        
        [_downloadConnectionsFilePaths addObject:filePath];
        [_downloadConnectionsWriteHandles addObject:fileWriteHandler];
    }
    [self continueConnectionQueue];
}

- (NSUInteger)maxAsyncConnections
{
    return _maxAsyncConnections;
}

- (void)setMaxAsyncConnections:(NSUInteger)max
{
    @synchronized(_downloadConnections)
    {
        _maxAsyncConnections = max;
    }
    [self continueConnectionQueue];
}

- (NSUInteger)activeConnections
{
    @synchronized(_downloadConnections)
    {
        return _activeConnections.count;
    }
}

- (NSUInteger)totalConnections
{
    @synchronized(_downloadConnections)
    {
        return _downloadConnections.count;
    }
}

- (void)continueConnectionQueue
{
    @synchronized(_downloadConnections)
    {
        if (_downloadConnections.count > _activeConnections.count && _activeConnections.count < _maxAsyncConnections)
        {
            NSURLConnection *connection = nil;
            for (NSURLConnection *conn in _downloadConnections)
            {
                if ([_activeConnections containsObject:conn]) continue;
                connection = conn;
                break;
            }
            if (!connection) return;
            [_activeConnections addObject:connection];
            [connection scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
            [connection start];
        }
    }
}

- (void)cancelAllConnections
{
    @synchronized(_downloadConnections)
    {
        for (NSURLConnection *conn in _activeConnections)
        {
            [conn cancel];
        }
        for (NSFileHandle *writeHandle in _downloadConnectionsWriteHandles)
        {
            [writeHandle closeFile];
        }
        for (NSString *tempFilePath in _downloadConnectionsFilePaths)
        {
            [[NSFileManager defaultManager] removeItemAtPath:tempFilePath error:nil];
        }
        _downloadConnections = nil;
        _downloadConnectionRequests = nil;
        _downloadConnectionsWriteHandles = nil;
        _downloadConnectionsFilePaths = nil;
        _activeConnections = nil;
    }
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    CGFloat pageWidth = scrollView.bounds.size.width;
    float fractionalPage = scrollView.contentOffset.x / pageWidth;
    NSInteger nearestNumber = lround(fractionalPage);
    if (nearestNumber != _currentSelectedImage)
    {
        _currentSelectedImage = nearestNumber;
    }
    
    int imageIndex1 = floor(fractionalPage);
    int imageIndex2 = ceil(fractionalPage);
    
    [self startDownloadForImageIndex:imageIndex1];
    [self startDownloadForImageIndex:imageIndex2];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    CGFloat pageWidth = scrollView.bounds.size.width;
    float fractionalPage = scrollView.contentOffset.x / pageWidth;
    NSInteger nearestNumber = lround(fractionalPage);
    
    [self startDownloadForImageIndex:nearestNumber];
    [self startDownloadForImageIndex:nearestNumber + 1];
}

- (void)startDownloadForImageIndex:(NSUInteger)index
{
    if (index == NSNotFound || index >= _startedDownload.count || _startedDownload[index] != (id)NSNull.null) return;
    
    NSString *cachePath = [DGFocusImageGallery getLocalCachePathForUrl:(NSURL *)_galleryUrls[index]];
    UIImage *viewImage = [UIImage imageWithContentsOfFile:cachePath];
    
    [_startedDownload replaceObjectAtIndex:index withObject:@(YES)];
    if (viewImage)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self createImageViewForImage:viewImage atIndex:index];
        });
    }
    else
    {
        CGRect scrollArea = _scrollView.bounds;
        scrollArea.origin.x = ((float)index) * scrollArea.size.width;
        
        UIActivityIndicatorView *view = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
        CGRect rc = [DGFocusImageGallery rectForWidth:view.frame.size.width
                                            andHeight:view.frame.size.height
                                              inFrame:scrollArea
                                      keepAspectRatio:YES
                                       fitFromOutside:NO
                                           cropAnchor:DGFocusImageGalleryCropAnchorCenterCenter];
        view.frame = rc;
        view.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        dispatch_async(dispatch_get_main_queue(), ^{
            [_scrollView addSubview:view];
            [view startAnimating];
        });
        [_imageViews replaceObjectAtIndex:index withObject:view];
        
        [self startDownloadingImageAtUrl:_galleryUrls[index]];
    }
}

@end
