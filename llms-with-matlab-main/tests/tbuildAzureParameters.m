classdef tbuildAzureParameters < matlab.unittest.TestCase
% Unit tests for llms.internal.buildAzureParameters

%   Copyright 2025-2026 The MathWorks, Inc.

    properties (Access = private)
        BasicMessages = {struct("role","user","content","Hello")};
        BasicFunctions = {struct("type","function","function",struct("name","test"))};
    end

    properties (TestParameter)
        VerbosityNonAuto = {"low", "medium", "high"};
        ReasoningEffortNonAuto = {"none", "minimal", "low", "medium", "high", "xhigh"};
    end

    methods (Test)
        function basicParameters(testCase)
            messages = testCase.BasicMessages;
            
            nvp = testCase.createNVP(Temperature=0.7, TopP=0.9, NumCompletions=2, ...
                StopSequences="stop1", MaxNumTokens=100, ...
                PresencePenalty=0.5, FrequencyPenalty=0.3);
            params = llms.internal.buildAzureParameters(messages, {}, nvp);
            
            testCase.verifyEqual(params.messages, messages);
            testCase.verifyEqual(params.temperature, 0.7);
            testCase.verifyEqual(params.top_p, 0.9);
            testCase.verifyEqual(params.n, 2);
            testCase.verifyEqual(params.stop, "stop1");
            testCase.verifyEqual(params.max_completion_tokens, 100);
            testCase.verifyEqual(params.presence_penalty, 0.5);
            testCase.verifyEqual(params.frequency_penalty, 0.3);
        end

        function streamDisabled(testCase)
            nvp = testCase.createNVP(StreamFun=[]);
            params = llms.internal.buildAzureParameters(testCase.BasicMessages, {}, nvp);
            testCase.verifyFalse(params.stream);
        end

        function streamEnabled(testCase)
            nvp = testCase.createNVP(StreamFun=@(x)disp(x));
            params = llms.internal.buildAzureParameters(testCase.BasicMessages, {}, nvp);
            testCase.verifyTrue(params.stream);
        end

        function infMaxTokensRemoved(testCase)
            nvp = testCase.createNVP(MaxNumTokens=inf);
            params = llms.internal.buildAzureParameters(testCase.BasicMessages, {}, nvp);
            testCase.verifyFalse(isfield(params, 'max_completion_tokens'));
        end

        function withTools(testCase)
            functions = testCase.BasicFunctions;
            nvp = testCase.createNVP(ToolChoice="auto");
            params = llms.internal.buildAzureParameters(testCase.BasicMessages, functions, nvp);
            testCase.verifyEqual(params.tools, functions);
            testCase.verifyEqual(params.tool_choice, "auto");
        end

        function withSeed(testCase)
            nvp = testCase.createNVP(Seed=42);
            params = llms.internal.buildAzureParameters(testCase.BasicMessages, {}, nvp);
            testCase.verifyEqual(params.seed, 42);
        end

        function jsonResponseFormat(testCase)
            nvp = testCase.createNVP(ResponseFormat="json");
            params = llms.internal.buildAzureParameters(testCase.BasicMessages, {}, nvp);
            testCase.verifyEqual(params.response_format.type, 'json_object');
        end

        function structResponseFormat(testCase)
            prototype = struct("name","","age",0);
            nvp = testCase.createNVP(ResponseFormat=prototype);
            params = llms.internal.buildAzureParameters(testCase.BasicMessages, {}, nvp);
            testCase.verifyEqual(params.response_format.type, 'json_schema');
            testCase.verifyTrue(isfield(params.response_format, 'json_schema'));
        end

        function verbosityAutoNotIncluded(testCase)
            nvp = testCase.createNVP(Verbosity="auto");
            params = llms.internal.buildAzureParameters(testCase.BasicMessages, {}, nvp);
            testCase.verifyThat(params, ~matlab.unittest.constraints.HasField('verbosity'));
        end

        function verbosityNonAutoIncluded(testCase, VerbosityNonAuto)
            nvp = testCase.createNVP(Verbosity=VerbosityNonAuto);
            params = llms.internal.buildAzureParameters(testCase.BasicMessages, {}, nvp);
            testCase.verifyEqual(params.verbosity, VerbosityNonAuto);
        end

        function reasoningEffortAutoNotIncluded(testCase)
            nvp = testCase.createNVP(ReasoningEffort="auto");
            params = llms.internal.buildAzureParameters(testCase.BasicMessages, {}, nvp);
            testCase.verifyThat(params, ~matlab.unittest.constraints.HasField('reasoning_effort'));
        end

        function reasoningEffortNonAutoIncluded(testCase, ReasoningEffortNonAuto)
            nvp = testCase.createNVP(ReasoningEffort=ReasoningEffortNonAuto);
            params = llms.internal.buildAzureParameters(testCase.BasicMessages, {}, nvp);
            testCase.verifyEqual(params.reasoning_effort, ReasoningEffortNonAuto);
        end
    end

    methods (Access = private)
        function nvp = createNVP(~, args)
            arguments
                ~
                args.ToolChoice = []
                args.Temperature = 1
                args.TopP = 1
                args.NumCompletions = 1
                args.StopSequences = []
                args.MaxNumTokens = inf
                args.PresencePenalty = 0
                args.FrequencyPenalty = 0
                args.ResponseFormat = "text"
                args.Seed = []
                args.StreamFun = []
                args.Verbosity = "auto"
                args.ReasoningEffort = "auto"
            end
            nvp = args;
        end
    end
end
