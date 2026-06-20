# Myweli - Beauty & Wellness Booking App

A native mobile application for iOS and Android, designed for Côte d'Ivoire and West Africa. Myweli connects customers with beauty salons, barbers, and wellness centers for easy appointment booking.

## Features

### MVP Features
- **User Authentication**: Phone number-based login with OTP verification
- **Provider Discovery**: Browse and search beauty salons, barbers, and spas
- **Service Booking**: Select services, choose date/time, and confirm appointments
- **Appointment Management**: View upcoming, past, and cancelled appointments
- **Provider Profiles**: Detailed information about each business with services and pricing

## Tech Stack

- **Framework**: Flutter (Dart)
- **State Management**: Provider
- **Navigation**: go_router
- **HTTP Client**: Dio (configured for future API integration)
- **Local Storage**: flutter_secure_storage
- **UI**: Material Design 3 with custom black & white theme

## Project Structure

```
mobile/
├── lib/
│   ├── main.dart                    # App entry point
│   ├── core/                        # Core functionality
│   │   ├── theme/                   # Design system
│   │   ├── constants/              # App constants
│   │   ├── utils/                   # Utilities
│   │   ├── router/                  # Navigation
│   │   └── di/                      # Dependency injection
│   ├── models/                      # Data models
│   ├── services/                    # API & mock services
│   │   ├── interfaces/             # Service interfaces
│   │   └── mock/                   # Mock implementations
│   ├── providers/                  # State management
│   ├── screens/                    # UI screens
│   └── widgets/                    # Reusable widgets
├── assets/                         # Images, fonts, etc.
└── pubspec.yaml                    # Dependencies
```

## Design System

Myweli uses a minimalistic black and white design:

- **Primary Color**: Black (#000000)
- **Background**: White (#FFFFFF)
- **Typography**: Inter font family
- **Spacing**: 8px grid system
- **Components**: Material Design 3 with custom styling

## Getting Started

### Prerequisites

- Flutter SDK (3.0.0 or higher)
- Dart SDK
- Android Studio / Xcode (for mobile development)

### Installation

1. Clone the repository
2. Navigate to the mobile directory:
   ```bash
   cd mobile
   ```

3. Install dependencies:
   ```bash
   flutter pub get
   ```

4. Run the app:
   ```bash
   flutter run
   ```

## Current Status

The app is currently built with **mock data services** to allow frontend-first development. All screens and user flows are functional with simulated data.

### Mock Services
- Authentication with OTP (always accepts "123456")
- Provider listings with sample salons and barbers
- Appointment booking and management
- Service catalogs

### Next Steps
- Backend API integration
- Real SMS OTP service
- Payment integration (Mobile Money)
- Push notifications
- Provider dashboard

## Screens

1. **Splash Screen**: App initialization
2. **Phone Login**: Enter phone number
3. **OTP Verification**: Verify with 6-digit code
4. **Home**: Browse featured and nearby providers
5. **Provider List**: Search and filter providers
6. **Provider Detail**: View services and book appointment
7. **Service Selection**: Choose services to book
8. **Date/Time Selection**: Pick appointment slot
9. **Booking Confirmation**: Review and confirm
10. **My Bookings**: View all appointments
11. **Appointment Detail**: View details and manage
12. **Profile**: User settings and logout

## Development Notes

- All services use interfaces for easy switching from mock to real API
- State management handled by Provider pattern
- Navigation uses go_router for type-safe routing
- Design tokens centralized in theme files
- Mock data includes realistic Côte d'Ivoire business examples

## License

Copyright © 2024 Myweli. All rights reserved.



