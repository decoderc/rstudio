/*
 * MenuCallbacks.mm
 *
 * Copyright (C) 2009-12 by RStudio, Inc.
 *
 * Unless you have received this program directly from RStudio pursuant
 * to the terms of a commercial license agreement with RStudio, then
 * this program is licensed to you under the terms of version 3 of the
 * GNU Affero General Public License. This program is distributed WITHOUT
 * ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING THOSE OF NON-INFRINGEMENT,
 * MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE. Please refer to the
 * AGPL (http://www.gnu.org/licenses/agpl-3.0.txt) for more details.
 *
 */


#import <Foundation/NSString.h>
#import <Cocoa/Cocoa.h>

#import "MainFrameController.h"

#import "MainFrameMenu.h"

@implementation MainFrameMenu

- (id)init
{
   if (self = [super init])
   {
      menuStack_ = [[NSMutableArray alloc] init];
      commands_ = [[NSMutableArray alloc] init];
      [commands_ addObject: @""]; // Make sure index 0 is not taken
   }
   return self;
}

- (void) dealloc
{
   [mainMenu_ release];
   [menuStack_ release];
   [commands_ release];
   [super dealloc];
}

- (void) beginMainMenu
{
   // create main menu
   mainMenu_ = [[NSMenu alloc] initWithTitle: @"MainMenu"];
   NSMenuItem* appMenuItem = [[NSMenuItem new] autorelease];
   [mainMenu_ addItem: appMenuItem];
   [NSApp setMainMenu: mainMenu_];
   
   // create app menu (currently just has quit)
   NSMenu* appMenu = [[NSMenu new] autorelease];
   NSMenuItem* quitMenuItem = [[[NSMenuItem alloc]
                                initWithTitle: @"Quit RStudio"
                                action: @selector(initiateQuit)
                                keyEquivalent:@"q"] autorelease];
   [quitMenuItem setTarget: [MainFrameController instance]];
   [appMenu addItem: quitMenuItem];
   [appMenuItem setSubmenu: appMenu];
}

- (void) beginMenu: (NSString*) menuName
{
   // remove ampersand
   menuName = [menuName stringByReplacingOccurrencesOfString:@"&"
                                                  withString:@""];

   if ([menuName isEqualToString: @"Help"]) {
      [self addWindowMenu];
   }

   // create the menu item and add it to the target
   NSMenuItem* menuItem = [[NSMenuItem new] autorelease];
   [menuItem setTitleWithMnemonic: menuName];
   [[self currentTargetMenu] addItem: menuItem];
   
   // create the menu and associate it with the menu item. we also
   // turn off "autoenable" so we can manage command states explicitly
   NSMenu* menu = [[[NSMenu alloc] initWithTitle: menuName] autorelease];
   [[self currentTargetMenu] setSubmenu: menu forItem: menuItem];
   
   // update the menu stack
   [menuStack_ addObject: menu];
}

- (void) addCommand: (NSString*) commandId
              label: (NSString*) label
            tooltip: (NSString*) tooltip
           shortcut: (NSString*) shortcut
        isCheckable: (Boolean) isCheckable
{
   // placeholder text for empty labels (can happen for MRU entries)
   if ([label length] == 0)
      label = @"Placeholder";
   
   // create menu item
   NSMenuItem* menuItem  = [[NSMenuItem new] autorelease];
   [menuItem setTitleWithMnemonic: label];
   [menuItem setToolTip: tooltip];

   [menuItem setTag: [commands_ count]];
   [commands_ addObject: commandId];
   [menuItem setTarget: self];
   [menuItem setAction: @selector(invoke:)];
   
   // TODO: reflect other menu state/behavior
   
   // add it to the menu
   [[self currentTargetMenu] addItem: menuItem];
}

- (void) addSeparator
{
   [[self currentTargetMenu] addItem: [NSMenuItem separatorItem]];
}

- (void) endMenu
{
   [menuStack_ removeLastObject];
}

- (void) endMainMenu
{
   [NSApp setMainMenu: mainMenu_];
}

- (NSMenu*) currentTargetMenu
{
   if ([menuStack_ count] == 0)
      return mainMenu_;
   else
      return [menuStack_ lastObject];
}

- (void) invoke: (id) sender {
   NSString* command = [commands_ objectAtIndex: [sender tag]];
   [[MainFrameController instance] invokeCommand: command];
}

- (BOOL) validateMenuItem: (NSMenuItem *) item {
   if ([item tag] == 0) {
      return YES;
   }

   NSString* command = [commands_ objectAtIndex: [item tag]];

   NSString* labelJs = [NSString stringWithFormat: @"window.desktopHooks.getCommandLabel(\"%@\");", command];
   [item setTitleWithMnemonic: [[MainFrameController instance] evaluateJavaScript: labelJs]];

   NSString* checkedJs = [NSString stringWithFormat: @"window.desktopHooks.isCommandChecked(\"%@\");", command];
   if ([[[MainFrameController instance] evaluateJavaScript: checkedJs] boolValue])
      [item setState: NSOnState];
   else
      [item setState: NSOffState];

   NSString* visibleJs = [NSString stringWithFormat: @"window.desktopHooks.isCommandVisible(\"%@\");", command];
   [item setHidden: ![[[MainFrameController instance] evaluateJavaScript: visibleJs] boolValue]];

   // Suppress any unnecessary separators. This code will run once per menu item which seems more
   // effort than necessary, but there's no guarantee that I know of that validateMenuItem will be
   // called from top to bottom, and it's fast anyway.
   NSMenu* menu = [item menu];
   bool suppressSep = TRUE; // When TRUE, we don't need any more seps at this point in the menu.
   NSMenuItem* trailingSep = Nil; // If non-null when we're done looping, an extraneous trailing sep.
   for (NSMenuItem* i in [menu itemArray]) {
      if ([i isSeparatorItem]) {
         [i setHidden: suppressSep];
         if (!suppressSep) {
            trailingSep = i;
            suppressSep = TRUE;
         }
      } else if (![i isHidden]) {
         // We've encountered a non-hidden, non-sep menu entry; the next sep should be shown.
         suppressSep = FALSE;
         trailingSep = Nil;
      }
   }
   if (trailingSep != Nil)
      [trailingSep setHidden: YES];

   NSString* enabledJs = [NSString stringWithFormat: @"window.desktopHooks.isCommandEnabled(\"%@\");", command];
   if ([[[MainFrameController instance] evaluateJavaScript: enabledJs] boolValue])
      return YES;
   else
      return NO;
}

- (void) addWindowMenu {
   NSMenuItem* windowMenuItem = [[NSMenuItem new] autorelease];
   [windowMenuItem setTitleWithMnemonic: @"Window"];
   [[self currentTargetMenu] addItem: windowMenuItem];

   NSMenu* windowMenu = [[[NSMenu alloc] initWithTitle: @"Window"] autorelease];
   [[self currentTargetMenu] setSubmenu: windowMenu forItem: windowMenuItem];

   NSMenuItem* minimize = [[NSMenuItem new] autorelease];
   [minimize setTitle: @"Minimize"];
   [minimize setTarget: self];
   [minimize setAction: @selector(minimize:)];
   [minimize setKeyEquivalent: @"m"];
   [minimize setKeyEquivalentModifierMask: NSCommandKeyMask];
   [minimize setAlternate: NO];
   [minimize setTag: 0];
   [windowMenu addItem: minimize];

   NSMenuItem* minimizeAll = [[NSMenuItem new] autorelease];
   [minimizeAll setTitle: @"Minimize All"];
   [minimizeAll setTarget: NSApp];
   [minimizeAll setAction: @selector(miniaturizeAll:)];
   [minimizeAll setKeyEquivalent: @"m"];
   [minimizeAll setKeyEquivalentModifierMask: NSCommandKeyMask | NSAlternateKeyMask];
   [minimizeAll setAlternate: YES];
   [minimizeAll setTag: 0];
   [windowMenu addItem: minimizeAll];

   NSMenuItem* zoom = [[NSMenuItem new] autorelease];
   [zoom setTitle: @"Zoom"];
   [zoom setTarget: self];
   [zoom setAction: @selector(zoom:)];
   [zoom setAlternate: NO];
   [zoom setTag: 0];
   [windowMenu addItem: zoom];

   NSMenuItem* zoomAll = [[NSMenuItem new] autorelease];
   [zoomAll setTitle: @"Zoom All"];
   [zoomAll setTarget: NSApp];
   [zoomAll setAction: @selector(zoomAll:)];
   [zoomAll setKeyEquivalentModifierMask: NSAlternateKeyMask];
   [zoomAll setAlternate: YES];
   [zoomAll setTag: 0];
   [windowMenu addItem: zoomAll];

   [windowMenu addItem: [NSMenuItem separatorItem]];

   NSMenuItem* bringAllToFront = [[NSMenuItem new] autorelease];
   [bringAllToFront setTitle: @"Bring All to Front"];
   [bringAllToFront setTarget: self];
   [bringAllToFront setAction: @selector(bringAllToFront:)];
   [bringAllToFront setKeyEquivalentModifierMask: NSAlternateKeyMask];
   [bringAllToFront setAlternate: YES];
   [bringAllToFront setTag: 0];
   [windowMenu addItem: bringAllToFront];

   [windowMenu addItem: [NSMenuItem separatorItem]];

   [NSApp setWindowsMenu: windowMenu];
}

- (void) minimize: (id) sender {
   [[NSApp keyWindow] performMiniaturize: sender];
}

- (void) zoom: (id) sender {
   [[NSApp keyWindow] performZoom: sender];
}

- (void) bringAllToFront: (id) sender {
   for (NSWindow* window in [NSApp windows]) {
      [window orderFront: self];
   }
}

+ (NSString *) webScriptNameForSelector: (SEL) sel
{
   if (sel == @selector(beginMenu:))
      return @"beginMenu";
   else if (sel == @selector(addCommand:label:tooltip:shortcut:isCheckable:))
      return @"addCommand";
     
   return nil;
}

+ (BOOL)isSelectorExcludedFromWebScript: (SEL) sel
{
   if (sel == @selector(currentTargetMenu))
      return YES;
   else
      return NO;
}

@end
