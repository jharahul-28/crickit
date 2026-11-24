# CricKit — Multi-Microservice Platform

CricKit is a distributed, multi-microservice platform designed for cricket organization, tournament management, authoritative ball-by-ball match scoring, real-time distribution, and career statistics.

## Tech Stack

- **Java**: 21
- **Spring Boot**: 4.2.0
- **Spring Cloud**: 2026.0.0
- **Build Tool**: Maven multi-module
- **Database**: PostgreSQL with Flyway
- **Messaging**: Apache Kafka
- **Service Discovery**: Netflix Eureka
- **API Gateway & Load Balancing**: Spring Cloud Gateway (WebFlux) + Spring Cloud LoadBalancer
- **Caching & Real-time**: Reactive Redis & WebFlux WebSocket distribution

## Microservices Architecture

| Application | Path | Type | Port | Description |
|---|---|---|---|---|
| **load-balancer** | `platform/load-balancer` | Reactive WebFlux | `8080` | Dedicated API Gateway and load-balancing application |
| **discovery-server** | `platform/discovery-server` | Servlet | `8761` | Netflix Eureka service discovery server |
| **identity-service** | `services/identity-service` | Servlet MVC | `8081` | User registration, authentication, OTP, JWT and session management |
| **organization-service** | `services/organization-service` | Servlet MVC | `8082` | Players, teams, memberships, captain and vice-captain management |
| **tournament-service** | `services/tournament-service` | Servlet MVC | `8083` | Tournament management, team registration, fixtures, scheduling and standings |
| **match-scoring-service** | `services/match-scoring-service` | Servlet MVC | `8084` | Match configuration, innings, cricket rules engine and authoritative ball-by-ball scoring |
| **live-service** | `services/live-service` | Reactive WebFlux | `8085` | WebSocket connections, real-time score distribution, spectator subscriptions and live snapshots |
| **statistics-service** | `services/statistics-service` | Servlet MVC | `8086` | Match statistics, tournament statistics, player career statistics and leaderboards |

## Build and Run

To build the entire project from root:

```bash
mvn clean compile
```

To run an individual service (e.g. `identity-service`):

```bash
cd services/identity-service
mvn spring-boot:run
```
