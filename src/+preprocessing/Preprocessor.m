classdef Preprocessor < handle
    properties
        PdfPath string
        OcrResult struct = struct([])
        Pages struct = struct([])
        TocPageIdx double = [];
        TocEntries struct = struct([])
        
        RegPageIdxFromToc double = []
        RegPageIdxFromRetrieval double = []
        RegPageIdxFromLLM double = []
        RegPageCandidateIdx double = []
        RegPageIdx double = []
        
        RegSumIdxFromToc double = []
        RegSumIdxFromRetrieval double = []
        RegSumIdxFromLLM double = []
        RegSumCandidateIdx double = []
        RegSumPageIdx double = []
        
        RegSummary struct = struct([])
        RegMap struct = struct([])

        BatchClient  openai.OpenaiBatch = openai.OpenaiBatch.empty
        MistralClient preprocessing.mistral.Mistral = preprocessing.mistral.Mistral.empty
        TaskRegSumVerfi preprocessing.page.PageBatchTask = preprocessing.page.PageBatchTask.empty
        TaskRegPageVerifi preprocessing.page.PageBatchTask = preprocessing.page.PageBatchTask.empty
        TaskAddDescpt preprocessing.page.PageBatchTask = preprocessing.page.PageBatchTask.empty
    end

    properties(Access=private)
        Config Config = Config.empty
    end
    
    methods
        function obj = Preprocessor(config)
            arguments
                config Config
            end

            pdfPath = string(config.Paths.PdfPath);
            if ~isfile(pdfPath)
                error("Preprocessor:MissingFile","No such file: %s",pdfPath);
            end
            
            obj.Config = config;
            obj.PdfPath = pdfPath;
            obj.BatchClient = openai.OpenaiBatch(config.getKey("openai"));
            obj.MistralClient = preprocessing.mistral.Mistral(config.getKey("mistral"));

        end
        
        function pipeline(obj)
            obj.runOcr();
            obj.classifyPages();
            obj.getRegPageCandidateIdx();

            obj.createVerificationTask(); % submit batch task1,2
            regSumCleanup = onCleanup(@() obj.TaskRegSumVerfi.cleanUp());
            regPageCleanup = onCleanup(@() obj.TaskRegPageVerifi.cleanUp());

            obj.waitAndCollect(obj.TaskRegSumVerfi); % collect taks1 result

            if ~isempty(obj.TaskRegSumVerfi)
                obj.RegSumPageIdx = preprocessing.page.parseVerificationContent( ...
                    obj.TaskRegSumVerfi.Contents, ...
                    obj.TaskRegSumVerfi.CustomIds, ...
                    obj.RegSumCandidateIdx);
            end
            
            obj.extractRegIndex(); % run chat task 3
            obj.waitAndCollect(obj.TaskRegPageVerifi); % collect taks2 result
            
            if ~isempty(obj.TaskRegPageVerifi)
                obj.RegPageIdx = preprocessing.page.parseVerificationContent( ...
                    obj.TaskRegPageVerifi.Contents, ...
                    obj.TaskRegPageVerifi.CustomIds, ...
                    obj.RegPageCandidateIdx);
            end
            
            obj.refineClassification();
            
            if ~allClassificationFalse(obj.Pages)
                obj.createAddDescriptionTask(); % submit batch taks5
                addDesCleanup = onCleanup(@() obj.TaskAddDescpt.cleanUp());
            end

            obj.extractRegMap(); % run chat task4
            obj.waitAndCollect(obj.TaskAddDescpt); % collcet task5 result
            if ~isempty(obj.TaskAddDescpt)
                obj.Pages = preprocessing.page.parseDescriptionContent(obj.Pages,obj.TaskAddDescpt.Contents,obj.TaskAddDescpt.CustomIds);
            end
        end

        function runOcr(obj,mistral)
            arguments
                obj (1,1) preprocessing.Preprocessor
                mistral (1,1) preprocessing.mistral.Mistral = obj.MistralClient
            end
            ocrConfig = obj.Config.Mistral.Task.Ocr; 
            
            ocrResult = mistral.runOcr( ...
                obj.PdfPath, ...
                Model=ocrConfig.Model, ...
                UrlExpiry=ocrConfig.UrlExpiry, ...
                IncludeImg=ocrConfig.IncludeImg, ...
                TableFormat=ocrConfig.TableFormat);
            
            pages = struct( ...
                'index',{ocrResult.pages.index}, ...
                'markdown', {ocrResult.pages.markdown}, ...
                'tables',  {ocrResult.pages.tables});
            pages = preprocessing.utils.removeHeaderFooter(pages);
            
            obj.OcrResult = ocrResult;
            obj.Pages = pages;
        end

        function saveOcrResult(obj,outputPath)
            jsonText = jsonencode(obj.OcrResult);
            fid = fopen(outputPath, "w");
        
            if fid == -1
                error("ocr:OutputFileOpenFailed", ...
                    "Failed to open file: %s", outputPath);
            end
            
            try
                fprintf(fid, "%s", jsonText);
                fclose(fid);
            catch ME
                if fid ~= -1
                    fclose(fid);
                end
                error("ocr:OutputFileWriteFailed", ...
                    "Failed to write to file: %s\n%s", outputPath, ME.message);
            end
        end

        function getRegPageCandidateIdx(obj)
            % Get register-map-page and register-summary page number from toc
            pages = preprocessing.toc.findTocPages(obj.Pages);
            tocIdx = find(arrayfun(@(onePage) onePage.result_toc.is_toc, pages));
            tocEntries = preprocessing.toc.extractTocEntry(pages(tocIdx));
            [regPageIdx,regSumIdx] = preprocessing.toc.resolveTocEntries(tocEntries);
            
            obj.RegPageIdxFromToc = regPageIdx;
            obj.RegSumIdxFromToc = regSumIdx;
            obj.TocEntries = tocEntries;
            obj.TocPageIdx = tocIdx;
            
            % Get register-map-page and register-summary page number through whole-text-retrieval
            pages = preprocessing.retrieval.findRelevantPageRange(pages,"register");
            regPageIdx = find(arrayfun(@(onePage) onePage.result_retrieval.is_reg_map_relevant, pages));
            regSumIdx = find(arrayfun(@(onePage) onePage.result_retrieval.is_reg_sum_relevant, pages));

            obj.RegPageIdxFromRetrieval = regPageIdx;
            obj.RegSumIdxFromRetrieval = regSumIdx;

            % Get register-map-page and register-summary page number from LLM
            regPageIdx = find(arrayfun(@(onePage) onePage.classification.is_register_map_relevant, pages));
            regSumIdx = find(arrayfun(@(onePage) onePage.classification.is_register_summary_relevant, pages));

            obj.RegPageIdxFromLLM = regPageIdx;
            obj.RegSumIdxFromLLM = regSumIdx;


            obj.RegPageCandidateIdx = unique([obj.RegPageIdxFromToc obj.RegPageIdxFromRetrieval obj.RegPageIdxFromLLM]);
            obj.RegSumCandidateIdx = unique([obj.RegSumIdxFromToc obj.RegSumIdxFromRetrieval obj.RegSumIdxFromLLM]);
            obj.Pages = pages;
        end

        function [contents,messages,batchLines] = classifyPages(obj)
            arguments
                obj (1,1) preprocessing.Preprocessor
            end
            import preprocessing.page.PageBatchTask
            import preprocessing.page.parseClassContent

            taskConfig = obj.Config.Openai.Task.classifyPages;
            funName = obj.getMethodName();
            inputName = funName +".jsonl";
            inputPath = fullfile(obj.Config.Paths.InputDir,inputName);

            classification = PageBatchTask( ...
                obj.Pages, ...
                obj.BatchClient, ...
                inputPath, ...
                taskConfig);

            classification.run();
            if ~classification.hasValidOutput
                error("Preprocessor:InvalidBatchOutput","Invalid Output from page classification");
            end

            contents = classification.Contents;
            messages = classification.Messages;
            batchLines = classification.BatchLines;
            obj.Pages = parseClassContent(obj.Pages,contents,classification.CustomIds);
        end

        function createVerificationTask(obj)
            obj.verifyRegSumPages();
            obj.verifyRegPages();
        end

        function verifyRegSumPages(obj)
            import preprocessing.page.PageBatchTask
            
            funName = obj.getMethodName();
            inputName = funName +".jsonl";
            inputPath = fullfile(obj.Config.Paths.InputDir,inputName);
            taskConfig = obj.Config.Openai.Task.verifyRegSumPages;

            if isempty(obj.RegSumCandidateIdx)
                obj.TaskRegSumVerfi = PageBatchTask.empty;
                return
            end
            
            regSumCandidates = obj.Pages(obj.RegSumCandidateIdx);
            regSumCandidates = rmfield(regSumCandidates,"classification");

            obj.TaskRegSumVerfi = PageBatchTask(...
                regSumCandidates, ...
                obj.BatchClient, ...
                inputPath, ...
                taskConfig);
            obj.TaskRegSumVerfi.submitBatch();
        end

        function verifyRegPages(obj)
            import preprocessing.page.PageBatchTask
            
            funName = obj.getMethodName();
            inputName = funName +".jsonl";
            inputPath = fullfile(obj.Config.Paths.InputDir,inputName);
            taskConfig = obj.Config.Openai.Task.verifyRegPages;

            if isempty(obj.RegPageCandidateIdx)
                obj.TaskRegPageVerifi = PageBatchTask.empty;
                return
            end
            
            regPageCandidates = obj.Pages(obj.RegPageCandidateIdx);
            regPageCandidates = rmfield(regPageCandidates,"classification");

            obj.TaskRegPageVerifi = PageBatchTask(...
                regPageCandidates, ...
                obj.BatchClient, ...
                inputPath, ...
                taskConfig);
            obj.TaskRegPageVerifi.submitBatch();
        end
        
        function extractRegIndex(obj)
            if isempty(obj.RegSumPageIdx)
                return
            end

            pages = struct( ...
                "index",    {obj.Pages.index}, ...
                "markdown", {obj.Pages.markdown}, ...
                "tables",   {obj.Pages.tables});

            taskPrompt = struct("pages", pages(obj.RegSumPageIdx));
            taskPrompt = jsonencode(taskPrompt);
            taskConfig = obj.Config.Openai.Task.extractRegIndex;
            
            regIdxExtractor = openai.OpenaiTaskAgent(obj.Config.getKey("openai"),taskPrompt,taskConfig);
            obj.RegSummary = regIdxExtractor.runTask();
        end

        function extractRegMap(obj)
            if isempty(obj.RegPageIdx)
                return
            end

            pages = struct( ...
                "index",    {obj.Pages.index}, ...
                "markdown", {obj.Pages.markdown}, ...
                "tables",   {obj.Pages.tables});

            if isempty(obj.RegSummary) || ~isfield(obj.RegSummary, "registers")
                registers = struct([]);
            else
                registers = obj.RegSummary.registers;
            end

            taskPrompt = struct("pages",pages(obj.RegPageIdx),"registers",registers);
            taskPrompt = jsonencode(taskPrompt);
            taskConfig = obj.Config.Openai.Task.extractRegMap;

            regMapExtractor = openai.OpenaiTaskAgent(obj.Config.getKey("openai"),taskPrompt,taskConfig);
            obj.RegMap = regMapExtractor.runTask();

        end

        function refineClassification(obj)
            for i = 1:numel(obj.Pages)
                if any(i == obj.RegSumPageIdx)
                    obj.Pages(i).classification.is_register_summary_relevant = true;
                else
                    obj.Pages(i).classification.is_register_summary_relevant = false;
                end

                if any(i == obj.RegPageIdx)
                    obj.Pages(i).classification.is_register_map_relevant = true;
                else
                    obj.Pages(i).classification.is_register_map_relevant = false;
                end
            end
        end

        function createAddDescriptionTask(obj)
            import preprocessing.page.PageBatchTask

            funName = obj.getMethodName();
            inputName = funName +".jsonl";
            inputPath = fullfile(obj.Config.Paths.InputDir,inputName);
            taskConfig = obj.Config.Openai.Task.addPageDescription;

            obj.TaskAddDescpt = PageBatchTask(...
                obj.Pages, ...
                obj.BatchClient, ...
                inputPath, ...
                taskConfig);
            obj.TaskAddDescpt.submitBatch();
        end

        function waitAndCollect(~,pageBatchTask)
            arguments
                ~
                pageBatchTask preprocessing.page.PageBatchTask
            end

            if isempty(pageBatchTask)
                return
            end
            pageBatchTask.waitBatch();
            pageBatchTask.collectBatchOutput();
            pageBatchTask.retryBatch();

            if ~pageBatchTask.hasValidOutput
                error("Preprocessor:InvalidBatchOutput","Invalid Output from: %s",pageBatchTask.Name);
            end
        end

    end
    
    methods (Access = private)
        function name = getMethodName(~)
            st = dbstack;
            name = string(st(2).name);
        end
    end
end

%% Helpers
function tf = allClassificationFalse(pages)
    arguments
        pages (1,:) struct
    end

    if isempty(pages)
        tf = true;
        return
    end

    classifications = [pages.classification];

    fieldNames = string(fieldnames(classifications));
    tf = true;

    for i = 1:numel(fieldNames)
        fieldName = fieldNames(i);
        values = [classifications.(fieldName)];

        if any(values)
            tf = false;
            return
        end
    end
end