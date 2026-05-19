# Analyze Table Data Using ChatGPT

This example shows how to generate suggestions for analyzing tabular data in MATLAB® using ChatGPT™.

First, build a prompt that describes table data to ChatGPT. Next, generate insights and suggestions for data analysis in MATLAB.

# Setup

Using the OpenAI® API requires an OpenAI API key. For information on how to obtain an OpenAI API key, as well as pricing, terms and conditions of use, and information about available models, see the OpenAI documentation at [https://platform.openai.com/docs/overview](https://platform.openai.com/docs/overview).

To connect to the OpenAI API from MATLAB using LLMs with MATLAB, specify the OpenAI API key as an environment variable and save it to a file called ".env".

![image_0.png](AnalyzeTableDataUsingChatGPTExample_media/image_0.png)

To connect to OpenAI, the ".env" file must be on the search path.

Load the environment file using the `loadenv` function.

```matlab
loadenv(".env")
```

# Describe Table to ChatGPT

Create a table containing data that represents domestic airline flights in the United States in 2008.

A sample of this dataset will be sent to the AI model as part of the system prompt.

```matlab
airlineData = readtable("airlinesmall_subset.xlsx",Sheet="2008");
```

Calculate summary statistics to describe the table variables. Include statistics that might be useful for string and numeric data.

```matlab
summaryStruct = summary(airlineData,Statistics=["nummissing" "numunique" "min" "max" "mean"]);
```

Convert the summary statistics to JSON\-formatted text.

```matlab
summaryString = string(jsonencode(summaryStruct,ConvertInfAndNaN=false));
```

To clearly identify rows in the table, add row labels. Then, capture a random 5\-row sample of the data.

```matlab
dataSample = airlineData;
dataSample = addvars(dataSample,"Row " + (1:height(dataSample))', ...
    NewVariableNames="RowLabels",Before=1);
rng default
randomIdx = randperm(height(dataSample),5);
randomIdx = sort(randomIdx);
dataSample = dataSample(randomIdx,:);
```

Convert the sample data to JSON\-formatted text.

```matlab
sampleString = string(jsonencode(dataSample,ConvertInfAndNaN=false));
```

Combine the summary and sample into a full description of the table.

```matlab
dataName = "airlineData";
dataDescription = "The MATLAB workspace contains a table with the name `" + dataName + "`." + newline + ...
    "Here are the basic summary statistics: " + newline + summaryString + newline + ...
    "Here is a random 5-row sample of the dataset: " + newline + sampleString;
```

Create a system prompt for ChatGPT that includes the data description. In the prompt, specify that responses typically include MATLAB code.

```matlab
systemPrompt = "You are a chat assistant designed to help analyze " + ...
    "tabular data using MATLAB. Your responses are concise and " + ...
    "typically contain MATLAB code snippets or suggest specific MATLAB functions." + ...
    newline + dataDescription;
```

Connect to the OpenAI Chat Completion API using the [`openAIChat`](../doc/functions/openAIChat.md) function. Specify the model name.

```matlab
mdl = openAIChat(systemPrompt,ModelName="gpt-4.1-mini");
```

# Ask ChatGPT Questions About Data

You can ask ChatGPT for insights into your data and suggestions for analysis in MATLAB. For example, you can ask for an overview of the data, or ask how to clean up the data and visualize it.

```matlab
generate(mdl,"Give me a high level overview of this dataset with a few interesting insights.")
```

```matlabTextOutput
ans = 
    "This airlineData dataset contains flight records from the year 2008, with 1753 entries. It includes details such as dates (Month, DayofMonth, DayOfWeek), times (Departure, Arrival times both actual and scheduled), airline carriers, flight numbers, tail numbers, elapsed times, delays, and cancellation/diversion status.
     
     Key variables:
     - Flight identifiers: UniqueCarrier (20 unique carriers), FlightNum, TailNum
     - Timing: DepTime, ArrTime, CRSDepTime, CRSArrTime, ActualElapsedTime, AirTime
     - Delays: ArrDelay, DepDelay, CarrierDelay, WeatherDelay, SecurityDelay, LateAircraftDelay
     - Locations: Origin and Dest airports (182 unique origins, 183 unique destinations)
     - Distances and Taxi times: Distance, TaxiIn, TaxiOut
     - Cancellation and diversion info
     
     Insight highlights:
     - The mean arrival delay is about 10 minutes, with a max delay of 567 minutes indicating some heavy delays.
     - The average flight distance is around 706 miles.
     - A small portion of flights were canceled (around 1.37%) or diverted (about 0.34%).
     - Many delay-related variables have >75% missing values which may reflect only delays when applicable.
     - The departure delay (mean ~11 minutes) is close to arrival delay, indicating delays accumulate through the flight.
     - There is variation in scheduled versus actual times, with some flights departing or arriving earlier/later than scheduled.
     - Taxi out times are generally longer than taxi in times (16.8 min vs 7 min average).
     
     Would you like a specific analysis or visualization for any aspect in this dataset?"


```

```matlab
generate(mdl,"Describe how I can clean up this data for further analysis in MATLAB.")
```

```matlabTextOutput
ans = 
    "To clean up the airlineData table for further analysis in MATLAB, you can follow these steps:
     
     1. Handle missing values:
        - Identify columns with missing values using `ismissing`.
        - For delay columns (CarrierDelay, WeatherDelay, etc.), replace missing with 0 if appropriate or remove rows with missing critical values.
     2. Remove or impute outliers if needed.
     3. Convert categorical variables from cell arrays to categorical type.
     4. Remove or filter canceled and diverted flights if your analysis excludes them.
     5. Fix data types for time columns if you need to analyze time (convert to datetime or duration).
     6. Remove unnecessary columns or rename for clarity.
     
     Here is example code snippets:
     
     ```matlab
     % 1. Replace NaNs in delay columns with zero
     delayCols = {'CarrierDelay','WeatherDelay','SDelay','SecurityDelay','LateAircraftDelay'};
     for i = 1:length(delayCols)
         col = delayCols{i};
         airlineData.(col)(ismissing(airlineData.(col))) = 0;
     end
     
     % 2. Convert cellular columns to categorical
     airlineData.UniqueCarrier = categorical(airlineData.UniqueCarrier);
     airlineData.Origin = categorical(airlineData.Origin);
     airlineData.Dest = categorical(airlineData.Dest);
     airlineData.CancellationCode = categorical(airlineData.CancellationCode);
     
     % 3. Remove canceled and diverted flights if needed
     airlineData = airlineData(airlineData.Cancelled==0 & airlineData.Diverted==0, :);
     
     % 4. Convert times to datetime or duration (optional)
     % For example, convert CRSDepTime and CRSArrTime to duration from midnight
     convertTime = @(t) hours(floor(t/100)) + minutes(mod(t,100));
     airlineData.CRSDepTime = convertTime(airlineData.CRSDepTime);
     airlineData.CRSArrTime = convertTime(airlineData.CRSArrTime);
     
     % 5. Remove or impute other missing values if needed (e.g., DepTime, ArrTime)
     % For example, remove rows with missing DepTime or ArrTime
     airlineData = airlineData(~ismissing(airlineData.DepTime) & ~ismissing(airlineData.ArrTime), :);
     ```
     
     This should prepare your data for subsequent analysis. Let me know if you need code for specific cleaning or preprocessing tasks."


```

```matlab
generate(mdl,"Give me a variety of visualizations I can create in MATLAB to explore this data.")
```

```matlabTextOutput
ans = 
    "Here are several types of visualizations you can create in MATLAB to explore the airlineData table:
     
     1. Histogram of Arrival Delays
     ```matlab
     histogram(airlineData.ArrDelay)
     xlabel('Arrival Delay (minutes)')
     ylabel('Frequency')
     title('Histogram of Arrival Delays')
     ```
     
     2. Boxplot of Departure Delays by Day of Week
     ```matlab
     boxplot(airlineData.DepDelay, airlineData.DayOfWeek)
     xlabel('Day of Week')
     ylabel('Departure Delay (minutes)')
     title('Departure Delays by Day of Week')
     ```
     
     3. Scatter plot of Distance vs Actual Elapsed Time
     ```matlab
     scatter(airlineData.Distance, airlineData.ActualElapsedTime)
     xlabel('Distance (miles)')
     ylabel('Actual Elapsed Time (minutes)')
     title('Distance vs Actual Elapsed Time')
     ```
     
     4. Bar chart of number of flights by Month
     ```matlab
     counts = groupcounts(airlineData.Month);
     bar(1:12, counts)
     xlabel('Month')
     ylabel('Number of Flights')
     title('Number of Flights per Month')
     ```
     
     5. Boxplot of Arrival Delay by Carrier
     ```matlab
     boxplot(airlineData.ArrDelay, airlineData.UniqueCarrier)
     xlabel('Carrier')
     ylabel('Arrival Delay (minutes)')
     title('Arrival Delay by Carrier')
     ```
     
     6. Scatter plot of DepDelay vs ArrDelay with color indicating Cancelled status
     ```matlab
     gscatter(airlineData.DepDelay, airlineData.ArrDelay, airlineData.Cancelled, 'br', 'xo')
     xlabel('Departure Delay (minutes)')
     ylabel('Arrival Delay (minutes)')
     title('Departure vs Arrival Delay by Cancelled Status')
     legend({'Not Cancelled', 'Cancelled'})
     ```
     
     7. Time series of average arrival delay by day
     ```matlab
     dailyAvgDelay = varfun(@mean, airlineData, 'InputVariables', 'ArrDelay', ...
         'GroupingVariables', {'Month', 'DayofMonth'});
     plot(datenum(2008, dailyAvgDelay.Month, dailyAvgDelay.DayofMonth), dailyAvgDelay.mean_ArrDelay)
     datetick('x', 'mmm-dd')
     xlabel('Date')
     ylabel('Average Arrival Delay (minutes)')
     title('Daily Average Arrival Delay')
     ```
     
     If you want code examples for any other specific visualizations or analyses, just ask!"


```

*Copyright 2026 The MathWorks, Inc.*