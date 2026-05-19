function job = runVerification(pages,batchClient,inputPath,taskConfig)
    arguments
        pages (1,:) struct
        batchClient (1,1) openai.OpenaiBatch
        inputPath (1,1) string
        taskConfig (1,1) struct
    end
      
    [~,name] = fileparts(inputPath);
    req = preprocessing.classification.buildPageRequest(pages,name);

    customIds = [req.id];
    userPrompts = [req.userPrompt];
    systemPrompt = fileread(taskConfig.PromptPath);
    
    job = batchClient.submitBatch( ...
        customIds, ...
        inputPath, ...
        userPrompts, ...
        Developer=systemPrompt, ...
        ModelName=taskConfig.ModelName, ...
        ResponseFormat=taskConfig.ResponseFormat, ...
        MaxCompletionTokens=taskConfig.MaxCompletionTokens);
end

