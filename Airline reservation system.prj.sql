-- Airports
CREATE TABLE Airports (
  AirportCode CHAR(3) PRIMARY KEY,
  Name VARCHAR(100) NOT NULL,
  City VARCHAR(100),
  Country VARCHAR(100)
);

-- Flights
CREATE TABLE Flights (
  FlightID SERIAL PRIMARY KEY,
  FlightNumber VARCHAR(10) NOT NULL,
  Origin CHAR(3) NOT NULL REFERENCES Airports(AirportCode),
  Destination CHAR(3) NOT NULL REFERENCES Airports(AirportCode),
  DepartureTime TIMESTAMP NOT NULL,
  ArrivalTime TIMESTAMP NOT NULL,
  SeatCapacity INT NOT NULL CHECK (SeatCapacity > 0),
  UNIQUE(FlightNumber, DepartureTime)
);

-- Customers
CREATE TABLE Customers (
  CustomerID SERIAL PRIMARY KEY,
  FirstName VARCHAR(50) NOT NULL,
  LastName VARCHAR(50) NOT NULL,
  Email VARCHAR(100) UNIQUE NOT NULL
);

-- Seats (individual seats per flight)
CREATE TABLE Seats (
  FlightID INT NOT NULL REFERENCES Flights(FlightID),
  SeatNumber VARCHAR(5) NOT NULL,
  Class VARCHAR(20),
  PRIMARY KEY (FlightID, SeatNumber)
);

-- Bookings
CREATE TABLE Bookings (
  BookingID SERIAL PRIMARY KEY,
  CustomerID INT NOT NULL REFERENCES Customers(CustomerID),
  FlightID INT NOT NULL REFERENCES Flights(FlightID),
  SeatNumber VARCHAR(5) NOT NULL,
  BookingTime TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  Status VARCHAR(20) NOT NULL DEFAULT 'Booked',
  UNIQUE (FlightID, SeatNumber),
  FOREIGN KEY (FlightID, SeatNumber) REFERENCES Seats(FlightID, SeatNumber)
);
-- Airports
INSERT INTO Airports VALUES
 ('BOM','Mumbai Intl','Mumbai','India'),
 ('DEL','Delhi Intl','New Delhi','India');

-- Flights
INSERT INTO Flights (FlightNumber, Origin, Destination, DepartureTime, ArrivalTime, SeatCapacity)
VALUES ('AI101','BOM','DEL','2025-08-01 08:00','2025-08-01 10:00',180);

-- Seats for FlightID = 1
INSERT INTO Seats
SELECT 1, LPAD(s::text,2,'0')||chr(65 + ((s-1)%6)), 'Economy'
FROM generate_series(1,30) AS s;

-- Customer
INSERT INTO Customers (FirstName, LastName, Email)
VALUES ('Amit','Sharma','amit.sharma@example.com');

-- Booking
INSERT INTO Bookings (CustomerID, FlightID, SeatNumber)
VALUES (1, 1, '01A');
SELECT s.SeatNumber
FROM Seats s
LEFT JOIN Bookings b
  ON b.FlightID = s.FlightID AND b.SeatNumber = s.SeatNumber AND b.Status = 'Booked'
WHERE s.FlightID = 1 AND b.BookingID IS NULL;
SELECT FlightID, FlightNumber, DepartureTime, ArrivalTime
FROM Flights
WHERE Origin = 'BOM' AND Destination = 'DEL'
  AND DepartureTime::date = '2025-08-01';
-- Prevent overbooking at insert
CREATE FUNCTION check_seat_capacity() RETURNS trigger AS $$
DECLARE cnt INT;
BEGIN
  SELECT COUNT(*) INTO cnt
    FROM Bookings
    WHERE FlightID = NEW.FlightID AND Status = 'Booked';
  PERFORM SeatCapacity FROM Flights WHERE FlightID = NEW.FlightID INTO STRICT cnt;
  IF cnt >= (SELECT SeatCapacity FROM Flights WHERE FlightID = NEW.FlightID) THEN
    RAISE EXCEPTION 'Flight is full';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_capacity
BEFORE INSERT ON Bookings
FOR EACH ROW EXECUTE FUNCTION check_seat_capacity();

-- Cancellation: free seat and log
CREATE FUNCTION trg_on_cancel() RETURNS trigger AS $$
BEGIN
  IF NEW.Status = 'Cancelled' THEN
    UPDATE Bookings SET Status = 'Cancelled' WHERE BookingID = OLD.BookingID;
    -- future: insert into audit log
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_booking_update
AFTER UPDATE ON Bookings
FOR EACH ROW WHEN (OLD.Status <> NEW.Status)
EXECUTE FUNCTION trg_on_cancel();
SELECT
  f.FlightNumber,
  COUNT(b.BookingID) FILTER (WHERE b.Status = 'Booked') AS SeatsBooked,
  f.SeatCapacity,
  (f.SeatCapacity - COUNT(b.BookingID) FILTER (WHERE b.Status = 'Booked')) AS SeatsAvailable
FROM Flights f
LEFT JOIN Bookings b ON f.FlightID = b.FlightID
GROUP BY f.FlightID, f.FlightNumber, f.SeatCapacity
ORDER BY f.FlightNumber;
