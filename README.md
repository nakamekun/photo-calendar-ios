# PhotoCalendarApp

PhotoCalendarApp is an iOS 17+ photo calendar built with SwiftUI and the Photos framework. It groups your photos by capture date and lets you choose one photo to represent each day.

## Features

- Requests photo library access and guides the user to Settings when access is denied
- Shows a monthly calendar with photo availability and daily pick states
- Displays a photo grid for each date
- Supports swipeable photo detail browsing for the same day
- Saves the selected daily photo as `YYYY-MM-DD -> PHAsset.localIdentifier`
- Includes an `On This Day` section for memories from the same month and day in past years

## Structure

- `PhotoCalendarApp/App`: app entry point
- `PhotoCalendarApp/Models`: calendar date, photo, and On This Day models
- `PhotoCalendarApp/Services`: photo permission, asset fetching, and selected photo storage
- `PhotoCalendarApp/ViewModels`: home, day photo, and library state logic
- `PhotoCalendarApp/Views`: calendar, photo list, detail, empty state, and permission screens

## Build

1. Open `PhotoCalendarApp.xcodeproj` in Xcode.
2. Set your Signing Team.
3. Run on a device or an iOS 17+ simulator.

## Verification Checklist

- The calendar appears after photo access is granted
- Days with photos show a dot
- Selecting a daily photo highlights the day cell
- Tapping a date shows only that day's photos
- Days with no photos show the empty state
- The photo detail screen supports horizontal swiping through photos from the same day
- `On This Day` shows photos from the same month and day in past years
- The Settings shortcut appears when photo access is denied
