# SQL Project 

## Background

### I. Adventure Works Bicycles 

Adventure Works is a fictional company that specializes in manufacturing bicycles (Microsoft, 2014a). The company’s product line includes 97 different brands of bikes, grouped into three categories: mountain bikes, road bikes, and touring bikes. In addition to manufacturing bicycles, Adventure Works also manufactures some of its own components. Other components are purchased from outside vendors, as well as all accessories and clothing.

Adventure Works is primarily in the business of selling bicycles, but it also sells accessories (such as bottles, bike racks, brakes, etc.), clothing (such as caps, gloves, jerseys, etc.), and components (such as brakes, chains, derailleurs, etc.). Many of these are manufactured by other companies so Adventure Works serves as a reseller. Adventure Works has a global presence, selling to customers throughout the United States, Canada, Australia, the United Kingdom, France, and Germany. The Adventure Works business model divides customers into two categories: retail stores that sell bikes, and individual customers. Although Adventure Works does not have any brick-and-mortar stores itself, the manufacturer does sell products directly to individuals via an Internet presence. Otherwise, Adventure Works sells in bulk to retail stores, which act as resellers for its products.

Adventure Works has a total of 290 employees, serving various functions such as sales, production, purchasing, engineering, finance, information services, marketing, shipping, and receiving, and R&D. Its customer base includes over 700 stores and over 19,000 individuals worldwide. Adventure Works utilizes the services of over 100 vendor companies that serve as suppliers of components, accessories, clothing, and raw materials.


### II. Adventure Works Bicycles – Scenarios
Sales and Marketing Scenario

Customer and sales-related information is a significant part of the Adventure Works sample database. This topic provides details about the customers that are represented in the sample database, a scheme of the major customers and sales tables and sample queries that demonstrate table relationships.

Customers

As a bicycle manufacturing company, Adventure Works Bicycles has two types of customers:
• Individuals. These are consumers who buy products from the Adventure Works Bicycles online store.
• Stores. These are retail or wholesale stores that buy products for resale from Adventure Works Bicycles sales representatives.
The column PersonType available in Person table indicates whether there is a store contact or individual (retail) customer.
Primary type of person: SC = Store Contact, IN = Individual (retail) customer, SP = Salesperson, EM = Employee (non-sales), VC = Vendor contact, GC = General contact

Product Scenario

This topic provides details about the product information that is represented in the Adventure Works sample database, a list of product-related tables, and sample queries that demonstrate common table relationships.

Product Overview

As a bicycle manufacturing company, Adventure Works Bicycles has the following main four product lines:
• Bicycles that are manufactured at the Adventure Works Bicycles company.
• Bicycle components that are replacement parts, such as wheels, pedals, or brake assemblies.
• Bicycle apparel that is purchased from vendors for resale to Adventure Works Bicycles customers.
• Bicycle accessories that are purchased from vendors for resale to Adventure Works Bicycles customers.

Purchasing and Vendor Scenario

At Adventure Works Bicycles, the purchasing department buys raw materials and parts used in the manufacture of Adventure Works Bicycles. Adventure Works Bicycles also purchases products for resale, such as bicycle apparel and bicycle add-ons like water bottles and pumps.
Manufacturing Overview
In the Adventure Works sample database, tables are provided that support the following typical manufacturing areas:
• Manufacturing processes:
o Bill of materials: Lists the products that are used or contained in another product.
o Work orders: Manufacturing orders by work center.
o Locations: Defines the major manufacturing and inventory areas, such as frame forming, paint, subassembly, and so on.
o Manufacturing and product assembly instructions by work center.
• Product inventory: The physical location of a product in the warehouse or manufacturing area, and the quantity available in that area.
• Engineering documentation: Technical specifications and maintenance documentation for bicycles or bicycle components.
Adventure Works schema details https://www.sqldatadictionary.com/AdventureWorks2014/

### III. Business problem – Stock Clearance

The leadership team wants to address a reoccurring problem that has been affecting the successful launch of new bicycles models.

By December time frame when new bicycles models are usually announced there is still a considerable stock of old bicycles models.

Last year Adventure Works Bicycles company implemented an aggressive discount campaign in weeks anteceding new models’ announcement. Despite those efforts that haven’t addressed the stock issue that prevented the successful launch of new bicycles models.

This year the leadership team decided to implement a new approach involving an online auction covering all products for which a new model was expected to be announced in the next 2 weeks. For the products covered in this campaign the initial bid price varies from 50% to 75% of the listed price.

Partner that will be extending online store website to support online auctions provided a list of the new application requirement that would involve extending current OLTP database relation model. This database is currently supporting internal ERP solution as an online website, so you have been delegated to extend current database model to support these new features. All new database objects should be created within Auction schema.

This campaign takes place during the last two weeks of November including Black Friday. During that day a high workload is expected so take that into consideration to ensure website reliability under high workload.

### IV. Stock Clearance - Functional specification
• Only products that are currently commercialized (both SellEndDate and DiscontinuedDate values not set).

• Initial bid price for products that are not manufactured in-house (MakeFlag value is 0) should be 75% of listed price

• For all other products initial bid prices should start at 50% of listed price

• By default, users can only increase bids by 5 cents (minimum increase bid) with maximum bid limit that is equal to initial product listed price. These thresholds should be easily configurable within a table so there is no need to change the database schema model. Note: These thresholds should be global and not per product/category.

## Guidelines

### Stored procedure name: uspAddProductToAuction
Stored procedure parameters: @ProductID [int], @ExpireDate [datetime], @InitialBidPrice [money]
Description: This stored procedure adds a product as auctioned.
Notes: Either @ExpireDate and @InitalBidPrice are optional parameters. If @ExpireDate is not specified, then auction should end in one week. If initial bid price is not specified, then should be 50% of product listed price unless falls into one exclusion mentioned above. Only one item for each ProductID can be simultaneously enlisted as an auction.



### Stored procedure name: uspTryBidProduct
Stored procedure parameters: @ProductID [int], @CustomerID [int], @BidAmount [money]
Description: This stored procedure adds a bid on behalf of that customer
Notes: @BidAmount is an optional parameter. If @BidAmount is not specified, then increase by threshold specified in thresholds configuration table.

### Stored procedure name: uspRemoveProductFromAuction
Stored procedure parameters: @ProductID [int]
Description: This stored procedure removes the product from being listed as auctioned even if there might have been bids for that product.
Notes: When users are checking their bid history this product should also show up as an auction cancelled

### Stored procedure name: uspListBidsOffersHistory
Stored procedure parameters: @CustomerID [int], @StartTime [datetime], @EndTime [datetime], @Active [bit]
Description: This stored procedure returns customer bid history for specified date time interval. If Active parameter is set to false, then all bids should be returned including ones related to products no longer
auctioned or purchased by customer. If Active set to true (default value) only returns products currently auctioned

### Stored procedure name: uspUpdateProductAuctionStatus
Stored procedure parameters: None
Description: This stored procedure updates auction status for all auctioned products. This stored procedure will be manually invoked before processing orders for dispatch.

### Deliverables:
- T-SQL script file named auction.sql used to extend AdventureWorks database schema
Notes:
- T-SQL script should be idempotent. Assume that database this script will execute against is named AdventureWorks.
- T-SQL script should also pre-populate any required configuration tables with default values. Being idempotent, this population should be just performed once no matter how many times t-SQL script is executed.
- All stored procedures should have proper error/exception handling mechanism.