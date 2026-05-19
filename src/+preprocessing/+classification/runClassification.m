function [pages,contents,messages,batchLines] = runClassification(pages,batchClient,inputPath,taskConfig,maxRetries)
    arguments
        pages (1,:) struct
        batchClient (1,1) openai.OpenaiBatch
        inputPath (1,1) string
        taskConfig (1,1) struct
        maxRetries (1,1) double {mustBeInteger,mustBeNonnegative} = 3
    end
    
    [~,name] = fileparts(inputPath);
    req = preprocessing.classification.buildClassificationRequest(pages);
    
    customIds = [req.id];
    userPrompts = [req.userPrompt];
    systemPrompt = fileread(taskConfig.PromptPath);    
    maxCompletionTokens = taskConfig.MaxCompletionTokens;
    
    [contents,messages,batchLines] = batchClient.runBatch( ...
        customIds, ...
        inputPath, ...
        userPrompts, ...
        Developer=systemPrompt, ...
        ModelName=taskConfig.ModelName, ...
        ResponseFormat=taskConfig.ResponseFormat, ...
        MaxCompletionTokens=maxCompletionTokens);
    
    %%Retry
    for i=1:maxRetries
        existingId = [contents.custom_id];
        notFinishedId = [contents([contents.not_finished]).custom_id];
        retryCustomId = [notFinishedId setdiff(customIds,existingId)];

        if isempty(retryCustomId) && numel(customIds) == numel(contents)
            break
        end

        retryNum = numel(retryCustomId);
        retryUser = strings(1,retryNum);

        for j = 1:numel(retryCustomId)
            idx = find(strcmp(customIds, retryCustomId(j)),1);
            retryUser(j) = userPrompts(idx);
        end

        if any(strcmp([contents.finish_reason],"length"))
            maxCompletionTokens = maxCompletionTokens + 500*i;
        end

        [retryContents,retryMessages,retryBatchLines] = batchClient.runBatch( ...
            retryCustomId, ...
            inputPath, ...
            retryUser, ...
            Developer=systemPrompt, ...
            ModelName=taskConfig.ModelName, ...
            ResponseFormat=taskConfig.ResponseFormat, ...
            MaxCompletionTokens=maxCompletionTokens);
    
        for j =1:numel(retryContents)
            customId = retryContents(j).custom_id;
            idx = find([contents.custom_id] == customId, 1);
            
            if isempty(idx)
                contents(end+1) = retryContents(j);
                messages(end+1) = retryMessages(j);
                batchLines(end+1) = retryBatchLines(j);
            else
                contents(idx) = retryContents(j);
                messages(idx) = retryMessages(j);
                batchLines(idx) = retryBatchLines(j);
            end
        end
    end
    
    defaultValue = preprocessing.classification.getDefaultFormat();

    for i = 1:numel(customIds)
        customId = customIds(i);
        contentIdx = find(strcmp(customId, [contents.custom_id]), 1);

        if isempty(contentIdx) || contents(contentIdx).not_finished
            pages(i).classification = defaultValue;
            continue
        end

        pages(i).classification = contents(contentIdx).content;
    end
end

