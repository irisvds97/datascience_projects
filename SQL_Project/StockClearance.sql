-- Create new schema - Auction
CREATE SCHEMA Auction;
GO

-- Create BidSettings table (MinimumIncreaseBid - in cents; MaximumBidPerc - percentage of product)
CREATE TABLE Auction.BidSettings (
    BidSettingsID INT IDENTITY(1,1) PRIMARY KEY,
    MinimumIncreaseBid MONEY,
    MaximumBidPerc DECIMAL(10, 2),
    StartBidDate DATETIME,
    StopBidDate DATETIME
);

-- Create AuctionStatus table
CREATE TABLE Auction.AuctionStatus (
    AuctionStatusID INT PRIMARY KEY,
    Status VARCHAR(20) NOT NULL
);

-- Create Auction table
CREATE TABLE Auction.Auction (
    AuctionID INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT NOT NULL FOREIGN KEY REFERENCES Production.Product(ProductId),
    EndDate DATETIME NOT NULL,
    BidPrice MONEY NOT NULL,
    HighestBidCustomerId INT FOREIGN KEY REFERENCES Sales.Customer(CustomerID),
    AuctionStatusID INT NOT NULL FOREIGN KEY REFERENCES Auction.AuctionStatus(AuctionStatusID)
);

-- Create Bid table
CREATE TABLE Auction.Bid (
    BidID INT IDENTITY(1,1) PRIMARY KEY,
    AuctionID INT NOT NULL FOREIGN KEY REFERENCES Auction.Auction(AuctionID),
    CustomerID INT NOT NULL FOREIGN KEY REFERENCES Sales.Customer(CustomerID), 
    BidAmount MONEY NOT NULL
);

-- Create BidHistory table
CREATE TABLE Auction.BidHistory (
    BidHistoryId INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT NOT NULL FOREIGN KEY REFERENCES Production.Product(ProductId),
    CustomerID INT FOREIGN KEY REFERENCES Sales.Customer(CustomerID), 
    History VARCHAR(MAX) NOT NULL,
    CreatedOn DATETIME NOT NULL
);

-- Insert Values into Tables
IF NOT EXISTS (SELECT 1 FROM Auction.BidSettings)
    BEGIN
        INSERT INTO Auction.BidSettings(MinimumIncreaseBid, MaximumBidPerc, StartBidDate, StopBidDate)
        VALUES (0.05, 1, '2023-11-12 00:00:00', '2023-11-25 23:59:59');
    END;

IF NOT EXISTS (SELECT 1 FROM Auction.AuctionStatus)
    BEGIN
        INSERT INTO Auction.AuctionStatus(AuctionStatusID, Status)
        VALUES
            (1, 'Auctioned'),
            (2, 'Completed'),
            (3, 'Cancelled');
    END;

GO

-- STORED PROCEDURES 

-- #1 Stored Procedure : uspAddProductToAuction - This stored procedure adds a product as auctioned
CREATE PROCEDURE uspAddProductToAuction 
    @ProductID INT,  
    @ExpireDate DATETIME = NULL,
    @InitialBidPrice MONEY = NULL
AS
BEGIN
    
    -- Declare parameters to be used
    DECLARE @CurrDateTime DATETIME = GETDATE()
    DECLARE @MaximumBidPerc DECIMAL(10, 2),
            @StartBidDate DATETIME,
            @StopBidDate DATETIME;
            (SELECT TOP 1 @MaximumBidPerc = MaximumBidPerc,
                          @StartBidDate = StartBidDate,
                          @StopBidDate =  StopBidDate
            FROM Auction.BidSettings)
    DECLARE @OriginalPrice MONEY = (SELECT TOP 1 ListPrice FROM Production.Product WHERE ProductID = @ProductID)
    
    -- Error: Only one item for each ProductID can be enlisted as an Auction 
    IF EXISTS (SELECT TOP 1 ProductID
               FROM Auction.Auction AS AU
               WHERE ProductID = @ProductID
                AND AuctionStatusID = 1)
    BEGIN
        RAISERROR('Product (ID: %d) already auctioned!', 16, 1, @ProductID) 
        RETURN 
    END

    -- Error: If Product cannot be auctioned
    IF @ProductID NOT IN (SELECT TOP 1 ProductID
                            FROM Production.Product
                            WHERE ProductID = @ProductID
                                AND SellEndDate IS NULL
                                AND DiscontinuedDate IS NULL)
    BEGIN
        RAISERROR('Product (ID: %d) cannot be auctioned', 16, 1, @ProductID)
        RETURN
    END

    -- Error: If ListPrice equals zero then it cannot be auctioned
    IF (@OriginalPrice = 0)
    BEGIN
        RAISERROR('Product (ID: %d) cannot be auctioned since its Original Price equals to zero', 16, 1, @ProductID)
        RETURN
    END

    -- If ExpireDate not specified - auction should end in one week
    IF (@ExpireDate IS NULL)
    BEGIN
        SET @ExpireDate = DATEADD(WEEK, 1, @CurrDateTime)
    END

    IF (@ExpireDate < @StartBidDate OR @ExpireDate > @StopBidDate)
    BEGIN
        RAISERROR('The expiration date provided is not within the campaign schedule. Please provide a valid expiration date.', 16, 1)
        RETURN
    END
    
    -- If initial bid is not specified - calculated by ListPrice
    IF (@InitialBidPrice IS NULL)
    BEGIN
        SET @InitialBidPrice = @OriginalPrice *
                                    (SELECT TOP 1 (CASE WHEN MakeFlag = 0 AND SellEndDate IS NULL THEN 0.75 ELSE 0.5 END)
                                    FROM Production.Product
                                    WHERE ProductID = @ProductID)
    END

    -- Round Bid Price to always have a maximum of 2 decimal cases
    SET @InitialBidPrice = ROUND(@InitialBidPrice, 2)

    -- Error: Check if the initial bid price exceeds the list price of the product
    IF (@InitialBidPrice > @OriginalPrice * @MaximumBidPerc) 
    BEGIN
        RAISERROR('The Initial Bid Price exceeds its possible value.', 16, 1)
        RETURN
    END
    
    -- Declare parameters to be used to insert record into BidHistory
    DECLARE @ProductName NVARCHAR(50) = (SELECT TOP 1 Name FROM Production.Product WHERE ProductId = @ProductID);
    DECLARE @History NVARCHAR(MAX) = 'Product ' + @ProductName + ' was auctioned with an Initial Bid Price of ' + CAST(@InitialBidPrice AS NVARCHAR(20)) + ' and an expire date of ' + CONVERT(NVARCHAR(30), @ExpireDate) + '.';
    
    BEGIN TRY
        BEGIN TRANSACTION
        -- Insert a product as auctioned
        INSERT INTO Auction.Auction(ProductID, EndDate, BidPrice, AuctionStatusID)
        VALUES (@ProductID, @ExpireDate, @InitialBidPrice, 1)
        -- Insert history of product into BidHistory 
        INSERT INTO Auction.BidHistory(ProductID, History, CreatedOn)
        VALUES (@ProductID, @History, @CurrDateTime)
        -- Commit transaction
        COMMIT
    END TRY    
    BEGIN CATCH
        -- Raise a user friendly error 
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
        -- Rollback transaction
        ROLLBACK TRANSACTION;
    END CATCH
END;

GO

-- #2 Stored Procedure : uspTryBidProduct - This stored procedure adds a bid on behalf of that customer
CREATE PROCEDURE uspTryBidProduct 
    @ProductID INT,  
    @CustomerID INT,
    @BidAmount MONEY = NULL

AS
BEGIN
    -- Declare parameters to be used in Stored Procedure
    
    -- Highest Bid corresponds to InitalValue or Latest bid
    DECLARE @HighestBid MONEY,
            @AuctionID INT; 
            SELECT TOP 1 @HighestBid = (CASE WHEN B.BidID IS NULL THEN A.BidPrice ELSE B.BidAmount END), 
                          @AuctionID = A.AuctionID
            FROM (SELECT *
                  FROM Auction.Auction
                  WHERE ProductID = @ProductID
                   AND AuctionStatusID = 1) AS A 
            LEFT JOIN Auction.Bid AS B ON A.AuctionID = B.AuctionID
            ORDER BY B.BidAmount DESC;
        
    -- Minimum Increase Bid and Maximum Bid Percentage parameters
    DECLARE @MinimumIncreaseBid DECIMAL(10, 2), 
            @MaximumBidPerc DECIMAL(10, 2);
        (SELECT TOP 1 @MinimumIncreaseBid = MinimumIncreaseBid, 
                      @MaximumBidPerc = MaximumBidPerc 
        FROM Auction.BidSettings)
    
    -- Original Product Price and Product Name
    DECLARE @OriginalPrice MONEY,
            @ProductName NVARCHAR(50);
        (SELECT TOP 1 @OriginalPrice = ListPrice,
                      @ProductName = Name
        FROM Production.Product 
        WHERE ProductID = @ProductID)
    
    -- Error: Customer Id must exist to create a Bid
    IF NOT EXISTS (SELECT TOP 1 *
                   FROM Sales.Customer C INNER JOIN Person.Person P ON C.PersonID = P.BusinessEntityID
                   WHERE C.CustomerID = @CustomerID)
    BEGIN
        RAISERROR('Cannot add a bid since the customer information is missing.', 16, 1)
        RETURN
    END

    -- Error: We can only add a bid if we already have an auction
    IF NOT EXISTS (SELECT TOP 1 *
                    FROM Auction.Auction
                    WHERE ProductID = @ProductID
                    AND AuctionStatusID = 1)
    BEGIN
        RAISERROR('Product (ID: %d) is not currently being auctioned.', 16, 1, @ProductID) 
        RETURN 
    END

    -- If Bid Amount is not specified increse threshold by specified in Auctions.BidSettings
    IF (@BidAmount IS NULL)
    BEGIN
        SET @BidAmount = @HighestBid + @MinimumIncreaseBid
    END

    -- Round Bid Amount to 2 decimal places
    SET @BidAmount = ROUND(@BidAmount, 2)

    -- Error: If Max Bid amount is exceeded throw error
    IF (@BidAmount > @OriginalPrice * @MaximumBidPerc)
    BEGIN
        RAISERROR('Bid Amount exceeds the maximum bid limit.', 16, 1)
        RETURN 
    END

    -- Error: Bid cannot be lower than the highest bid made so far
    IF (@BidAmount <= @HighestBid)
    BEGIN
        RAISERROR('The bid amount is lower or equal the current highest bid. Please make a higher bid.', 16, 1)
        RETURN
    END
 
    -- Error: If a customer holds the highest bid, he cannot bid on the same product
    IF EXISTS (
        SELECT TOP 1 1
        FROM Auction.Bid B
        INNER JOIN Auction.Auction A ON A.AuctionID = B.AuctionID
        WHERE A.ProductID = @ProductID
            AND B.BidAmount = @HighestBid
            AND B.CustomerID = @CustomerID
    )
    BEGIN
        RAISERROR('You already have the highest bid. You cannot bid again on the same item.', 16, 1)
        RETURN
    END
    
    -- Declare parameters to be used to insert record into BidHistory
    DECLARE @CustomerName NVARCHAR(100) = (SELECT TOP 1 CONCAT(P.FirstName, ' ', P.LastName)
                                        FROM Sales.Customer C INNER JOIN Person.Person P ON C.PersonID = P.BusinessEntityID
                                        WHERE C.CustomerID = @CustomerID)
    DECLARE @History VARCHAR(MAX) = 'A bid on Product ' + @ProductName + ' was made by Customer ' + @CustomerName + ' at the value of ' + CAST(@BidAmount AS VARCHAR(20)) + '.'

    BEGIN TRY
        BEGIN TRANSACTION
            -- Insert Bid into database
            INSERT INTO Auction.Bid(AuctionID, CustomerID, BidAmount)
            VALUES (@AuctionID, @CustomerID, @BidAmount)
            -- Insert history of product into BidHistory 
            INSERT INTO Auction.BidHistory(ProductID, CustomerID, History, CreatedOn)
            VALUES (@ProductID, 
                    @CustomerID,
                    @History, 
                    GETDATE())
            -- Commit transaction
            COMMIT
    END TRY
    BEGIN CATCH
        -- Raise a user friendly error 
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
        -- Rollback transaction
        ROLLBACK TRANSACTION;
    END CATCH
END;

GO

-- #3 Stored Procedure : uspRemoveProductFromAuction - This stored procedure removes the product from being listed as auctioned even if there might have been bids for that product.
CREATE PROCEDURE uspRemoveProductFromAuction 
    @ProductID INT
AS
BEGIN
    -- Declare parameters to be used to insert record into BidHistory
    DECLARE @ProductName NVARCHAR(50) = (SELECT TOP 1 Name FROM Production.Product WHERE ProductId = @ProductID)
    DECLARE @History VARCHAR(MAX) = 'Product ' + @ProductName + ' has been removed from auctions.'

    -- Check if Product Exists in Auctions
    IF NOT EXISTS (SELECT TOP 1 * FROM Auction.Auction WHERE ProductID = @ProductID)
    BEGIN
        RAISERROR('Product (ID: %d) cannot be deleted since it is not auctioned.', 16, 1, @ProductID) 
        RETURN 
    END

    BEGIN TRY
        BEGIN TRANSACTION
            -- Delete Product from Bids
            DELETE B
            FROM Auction.Bid B INNER JOIN Auction.Auction A on B.AuctionID = A.AuctionID
            WHERE A.ProductID = @ProductID
            -- Delete Product from Auction
            DELETE Auction.Auction
            FROM Auction.Auction
            WHERE Auction.Auction.ProductID = @ProductID
            -- Insert history of product into BidHistory
            INSERT INTO Auction.BidHistory(ProductID, History, CreatedOn)
            VALUES (@ProductID, 
                    @History, 
                    GETDATE())
            -- Commit transaction
            COMMIT
    END TRY 
    BEGIN CATCH
        -- Raise a user friendly error 
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
        -- Rollback transaction
        ROLLBACK TRANSACTION;
    END CATCH
END;

GO

-- #4 Stored Procedure : uspListBidsOffersHistory - This stored procedure returns customer bid history for specified date time interval
CREATE PROCEDURE uspListBidsOffersHistory 
    @CustomerID INT,
    @StartTime DATETIME,
    @EndTime DATETIME,
    @Active BIT = 1
AS
BEGIN
    -- Error: Start Time cannot be later than End Time
    IF(@StartTime > @EndTime)
    BEGIN
        RAISERROR('Start Time should be prior to the End Time.', 16, 1) 
        RETURN 
    END
    
    -- Select history data
    SELECT BD.History, BD.CreatedOn
    FROM Auction.BidHistory BD
        LEFT JOIN Production.Product P ON BD.ProductID = P.ProductID
    WHERE BD.CustomerID = @CustomerID
        AND BD.CreatedOn >= @StartTime
        AND BD.CreatedOn <= @EndTime
        -- Active = False or Retrieve History for products that are Auctioned
        AND (@Active = 0 
            OR 
            (P.ProductID IN (SELECT ProductID 
                            FROM Auction.Auction
                            WHERE AuctionStatusID = 1)))
    ORDER BY BD.CreatedOn DESC
END;

GO

-- #5 Stored Procedure : uspUpdateProductAuctionStatus
CREATE PROCEDURE uspUpdateProductAuctionStatus 
AS
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION
            -- Completed Auctions
            -- BidHistory 
            INSERT INTO Auction.BidHistory(ProductID, CustomerID, History, CreatedOn)
            (SELECT A.ProductID, 
                    (SELECT TOP 1 CustomerID FROM Auction.Bid WHERE AuctionID = A.AuctionID ORDER BY BidAmount DESC),
                    'Customer ' + P.FirstName + ' ' + P.LastName + ' has won product ' + PR.Name, 
                    GETDATE()
            FROM Auction.Auction A
            JOIN Production.Product PR ON PR.ProductID = A.ProductID
            JOIN Person.Person P ON P.BusinessEntityID = 
                (SELECT TOP 1 C.PersonID FROM Auction.Bid B JOIN Sales.Customer C ON B.CustomerID = C.CustomerID WHERE AuctionID = A.AuctionID ORDER BY BidAmount DESC)
            WHERE EXISTS (SELECT * FROM Auction.Bid B WHERE B.AuctionID = A.AuctionID)
                AND GETDATE() > EndDate
                AND A.AuctionStatusID = 1)
            -- Update Auction to set status
            UPDATE Auction.Auction
            SET AuctionStatusID = 2,
                BidPrice = (SELECT MAX(BidAmount) FROM Auction.Bid WHERE AuctionID = Auction.Auction.AuctionID),
                HighestBidCustomerId = (SELECT TOP 1 CustomerID FROM Auction.Bid WHERE AuctionID = Auction.Auction.AuctionID ORDER BY BidAmount DESC)
            WHERE EXISTS (SELECT * FROM Auction.Bid B WHERE B.AuctionID = Auction.Auction.AuctionID)
                AND GETDATE() > EndDate
                AND Auction.Auction.AuctionStatusID = 1

            -- Cancelled Auctions
            -- BidHistory 
            INSERT INTO Auction.BidHistory(ProductID, History, CreatedOn)
            (SELECT A.ProductID, 
                    'Auction of product ' + PR.Name + ' has been cancelled as there were no Bids made for this product.', 
                    GETDATE()
            FROM Auction.Auction A JOIN Production.Product PR ON PR.ProductID = A.ProductID
            WHERE NOT EXISTS (SELECT * FROM Auction.Bid B WHERE B.AuctionID = A.AuctionID)
                AND GETDATE() > EndDate
                AND A.AuctionStatusID = 1)
            -- Update Auction to set status
            UPDATE Auction.Auction
            SET AuctionStatusID = 3
            WHERE NOT EXISTS (SELECT * FROM Auction.Bid B WHERE B.AuctionID = Auction.Auction.AuctionID)
                AND GETDATE() > EndDate
                AND Auction.Auction.AuctionStatusID = 1
            
            -- Commit transaction
            COMMIT
    END TRY
    BEGIN CATCH
        -- Raise a user friendly error 
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
        -- Rollback transaction
        ROLLBACK TRANSACTION;
    END CATCH
END;